class_name LobbyMemberSync
extends Node
## Registry of the lobby members and of the shared lobby data, synchronized by RPC.
##
## The host is the only authority: it admits players, resolves their identity, validates
## every change and tells the others. Clients never trust each other.
## Being RPC based, it behaves the same on every backend.
##
## This node receives RPCs: it must have the same name and path on every peer.

signal member_added(member: LobbyMember)
signal member_removed(member: LobbyMember)
signal member_updated(member: LobbyMember, key: String)
signal lobby_data_changed(key: String)
## Client: the host admitted the local player and sent the registry.
signal admitted
## Client: the host asked the local player to leave.
signal dismissed(reason: LobbyTypes.Reason)

const MAX_KEY_LENGTH: int = 64
const MAX_VALUE_BYTES: int = 4096

## Admitted players, by peer id.
var members: Dictionary[int, LobbyMember] = {}
var local_member: LobbyMember
## Data shared by the whole lobby (selected map, game mode...). Only the host writes it.
var lobby_data: Dictionary[String, Variant] = {}

## Host: extra admission rule, `func(user_id: int) -> LobbyTypes.Reason`.
## Return `Reason.NONE` to admit the player.
var admission_check: Callable
## Host: optional validation of member data, `func(member: LobbyMember, key: String, value: Variant) -> bool`.
var data_validator: Callable
## Keys of member data only the host may write: a request of a member for one of them is
## ignored. Add the keys the game decides for the players (team, role...).
var host_only_keys: Array[String] = [LobbyMember.PING_KEY]

var _config: LobbyConfig
var _backend: LobbyBackend
var _banned_user_ids: Array[int] = []
## Peers connected to the host that did not introduce themselves yet.
var _pending_peers: Array[int] = []
## Members asked to leave and not gone yet: nothing they ask is accepted anymore.
var _dismissed_peers: Array[int] = []
## Incremented on every reset, so timers started for a previous lobby are ignored.
var _session: int = 0

func setup(config: LobbyConfig, backend: LobbyBackend) -> void:
	_config = config
	_backend = backend

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

## Host: starts a registry containing only the local player.
func start_host() -> void:
	reset()
	var identity: Dictionary = _backend.get_local_identity()
	local_member = LobbyMember.new(
		MultiplayerPeer.TARGET_PEER_SERVER, _read_int(identity, "user_id"), _read_string(identity, "name")
	)
	members[local_member.peer_id] = local_member
	member_added.emit(local_member)

func reset() -> void:
	_session += 1
	members.clear()
	lobby_data.clear()
	local_member = null
	_banned_user_ids.clear()
	_pending_peers.clear()
	_dismissed_peers.clear()

func is_host() -> bool:
	return local_member != null and local_member.is_host

func get_member(peer_id: int) -> LobbyMember:
	return members.get(peer_id)

## Sets data on a member. A client can only write its own data, the host can write anyone's.
## A null value erases the key.
func set_member_data(key: String, value: Variant, member: LobbyMember = null) -> void:
	if local_member == null:
		return
	var target: LobbyMember = member if member != null else local_member
	if is_host():
		_host_set_member_data(target, key, value)
	elif target == local_member:
		_request_member_data.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, key, value)

## Host only. Writes data decided by the lobby itself, without asking the game validator.
func set_member_data_as_host(member: LobbyMember, key: String, value: Variant) -> void:
	if is_host():
		_host_set_member_data(member, key, value, false)

## Host only. A null value erases the key.
func set_lobby_data(key: String, value: Variant) -> void:
	if not is_host() or not _is_valid_entry(key, value):
		return
	_apply_lobby_data(key, value)
	for peer_id: int in _remote_peers():
		_lobby_data_set.rpc_id(peer_id, key, value)

## Host only. Asks a player to leave the lobby. With `ban`, the same user is refused
## until the lobby closes.
## The player stays a member until it is really gone, which takes at most
## `LobbyConfig.dismiss_grace`: it is asked to leave by itself, because some backends
## (Steam) cannot remove a lobby member, and because what it was still sending must
## reach the others before they forget it.
func dismiss(peer_id: int, reason: LobbyTypes.Reason, ban: bool = false) -> void:
	if not multiplayer.is_server() or peer_id == MultiplayerPeer.TARGET_PEER_SERVER:
		return
	var member: LobbyMember = get_member(peer_id)
	if member != null and ban and not _banned_user_ids.has(member.user_id):
		_banned_user_ids.append(member.user_id)
	_pending_peers.erase(peer_id)
	if not multiplayer.get_peers().has(peer_id):
		_remove_member(peer_id)
		return
	if _dismissed_peers.has(peer_id):
		return
	_dismissed_peers.append(peer_id)
	_dismissed.rpc_id(peer_id, reason)
	_disconnect_later(peer_id, _config.dismiss_grace)

# --- Admission ---------------------------------------------------------------------------

func _on_connected_to_server() -> void:
	_hello.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, {
		"game_key": _config.game_key,
		"protocol_version": _config.protocol_version,
		"identity": _backend.get_local_identity(),
	})

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_pending_peers.append(peer_id)
	_disconnect_later(peer_id, _config.join_timeout, true)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_pending_peers.erase(peer_id)
	_dismissed_peers.erase(peer_id)
	_remove_member(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _hello(claim: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if members.has(peer_id) or not _pending_peers.has(peer_id):
		return
	_pending_peers.erase(peer_id)
	var identity: Dictionary = {}
	var reason: LobbyTypes.Reason = _check_version(claim)
	if reason == LobbyTypes.Reason.NONE:
		var claimed_identity: Variant = claim.get("identity")
		identity = _backend.resolve_identity(
			peer_id, claimed_identity if claimed_identity is Dictionary else {}
		)
		reason = _check_admission(identity)
	if reason != LobbyTypes.Reason.NONE:
		dismiss(peer_id, reason)
		return
	var member: LobbyMember = LobbyMember.new(
		peer_id, _read_int(identity, "user_id"), _read_string(identity, "name")
	)
	var other_peers: Array[int] = _remote_peers()
	members[peer_id] = member
	var snapshot: Array[Dictionary] = []
	for existing: LobbyMember in members.values():
		snapshot.append(existing.to_dict())
	_snapshot.rpc_id(peer_id, snapshot, lobby_data)
	for other_peer_id: int in other_peers:
		_member_added.rpc_id(other_peer_id, member.to_dict())
	member_added.emit(member)

func _check_version(claim: Dictionary) -> LobbyTypes.Reason:
	if claim.get("game_key") != _config.game_key:
		return LobbyTypes.Reason.VERSION_MISMATCH
	if claim.get("protocol_version") != _config.protocol_version:
		return LobbyTypes.Reason.VERSION_MISMATCH
	return LobbyTypes.Reason.NONE

func _check_admission(identity: Dictionary) -> LobbyTypes.Reason:
	if identity.is_empty():
		return LobbyTypes.Reason.CONNECTION_FAILED
	var user_id: int = _read_int(identity, "user_id")
	if _banned_user_ids.has(user_id):
		return LobbyTypes.Reason.BANNED
	if members.size() >= _config.max_players:
		return LobbyTypes.Reason.LOBBY_FULL
	if admission_check.is_valid():
		var result: LobbyTypes.Reason = admission_check.call(user_id)
		return result
	return LobbyTypes.Reason.NONE

@rpc("authority", "call_remote", "reliable")
func _snapshot(member_dicts: Array, data: Dictionary) -> void:
	members.clear()
	lobby_data.clear()
	for key: Variant in data:
		if key is String:
			lobby_data[key] = data[key]
	for member_dict: Variant in member_dicts:
		if member_dict is not Dictionary:
			continue
		var member: LobbyMember = LobbyMember.from_dict(member_dict)
		if member != null:
			members[member.peer_id] = member
	local_member = get_member(multiplayer.get_unique_id())
	if local_member == null:
		return
	for member: LobbyMember in members.values():
		member_added.emit(member)
	admitted.emit()

@rpc("authority", "call_remote", "reliable")
func _member_added(member_dict: Dictionary) -> void:
	var member: LobbyMember = LobbyMember.from_dict(member_dict)
	if member == null or local_member == null:
		return
	members[member.peer_id] = member
	member_added.emit(member)

@rpc("authority", "call_remote", "reliable")
func _member_removed(peer_id: int) -> void:
	_erase_member(peer_id)

@rpc("authority", "call_remote", "reliable")
func _dismissed(reason: LobbyTypes.Reason) -> void:
	dismissed.emit(reason)

func _remove_member(peer_id: int) -> void:
	if not members.has(peer_id):
		return
	_erase_member(peer_id)
	for other_peer_id: int in _remote_peers():
		_member_removed.rpc_id(other_peer_id, peer_id)

func _erase_member(peer_id: int) -> void:
	var member: LobbyMember = get_member(peer_id)
	if member == null:
		return
	members.erase(peer_id)
	member_removed.emit(member)

func _disconnect_later(peer_id: int, delay: float, only_if_pending: bool = false) -> void:
	var session: int = _session
	get_tree().create_timer(delay).timeout.connect(
		func() -> void:
			if session != _session or not multiplayer.has_multiplayer_peer():
				return
			if only_if_pending and not _pending_peers.has(peer_id):
				return
			if multiplayer.is_server() and multiplayer.get_peers().has(peer_id):
				multiplayer.multiplayer_peer.disconnect_peer(peer_id)
				# Not every transport reports a disconnection it started itself.
				_on_peer_disconnected(peer_id)
	)

# --- Data --------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_member_data(key: String, value: Variant) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var member: LobbyMember = get_member(peer_id)
	if member != null and not _dismissed_peers.has(peer_id) and not host_only_keys.has(key):
		_host_set_member_data(member, key, value)

func _host_set_member_data(
	member: LobbyMember, key: String, value: Variant, ask_validator: bool = true
) -> void:
	if not members.has(member.peer_id) or not _is_valid_entry(key, value):
		return
	if ask_validator and data_validator.is_valid() and data_validator.call(member, key, value) != true:
		return
	_apply_member_data(member.peer_id, key, value)
	for peer_id: int in _remote_peers():
		_member_data_set.rpc_id(peer_id, member.peer_id, key, value)

@rpc("authority", "call_remote", "reliable")
func _member_data_set(peer_id: int, key: String, value: Variant) -> void:
	_apply_member_data(peer_id, key, value)

@rpc("authority", "call_remote", "reliable")
func _lobby_data_set(key: String, value: Variant) -> void:
	_apply_lobby_data(key, value)

func _apply_member_data(peer_id: int, key: String, value: Variant) -> void:
	var member: LobbyMember = get_member(peer_id)
	if member == null:
		return
	if value == null:
		member.data.erase(key)
	else:
		member.data[key] = value
	member_updated.emit(member, key)

func _apply_lobby_data(key: String, value: Variant) -> void:
	if value == null:
		lobby_data.erase(key)
	else:
		lobby_data[key] = value
	lobby_data_changed.emit(key)

func _is_valid_entry(key: String, value: Variant) -> bool:
	if key.is_empty() or key.length() > MAX_KEY_LENGTH:
		return false
	if value is Object:
		return false
	return var_to_bytes(value).size() <= MAX_VALUE_BYTES

# --- Helpers -----------------------------------------------------------------------------

## Peer ids of every admitted member except the local one.
func _remote_peers() -> Array[int]:
	var peers: Array[int] = []
	for peer_id: int in members:
		if local_member == null or peer_id != local_member.peer_id:
			peers.append(peer_id)
	return peers

func _read_int(dict: Dictionary, key: String) -> int:
	var value: Variant = dict.get(key)
	return value if value is int else 0

func _read_string(dict: Dictionary, key: String) -> String:
	var value: Variant = dict.get(key)
	return value if value is String else ""
