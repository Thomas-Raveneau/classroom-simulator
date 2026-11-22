class_name LobbyService
extends Node
## The single entry point of the lobby, available as the `Lobby` autoload.
##
## Create, join and leave lobbies, read the members and their data, start the game.
## The UI and the game only talk to this class; it talks to a `LobbyBackend`
## (Steam, ENet...) and never the other way around.
##
## This class never references the autoload by name: use `LobbyService.for_node(self)`
## from reusable code, so several services can live in the same process (tests).

signal state_changed(state: LobbyTypes.State)
## The local player created a lobby and is its host.
signal created
## The local player was admitted in a lobby.
signal joined
## Emitted after `created` or `joined`.
signal entered
signal create_failed(reason: LobbyTypes.Reason)
signal join_failed(reason: LobbyTypes.Reason)
## The local player is not in the lobby anymore, whatever the cause.
signal left(reason: LobbyTypes.Reason)
## A player was admitted. When joining, also emitted for every member already there.
signal member_joined(member: LobbyMember)
signal member_left(member: LobbyMember)
## A piece of data of a member changed (`LobbyMember.READY_KEY` for the ready flag).
signal member_updated(member: LobbyMember, key: String)
signal lobby_data_changed(key: String)
signal visibility_changed(visibility: LobbyTypes.Visibility)
## The game scene is loaded on every member: the local player is in game.
signal game_started
## A member has the game scene loaded: the right moment to spawn what belongs to it.
## Emitted for every member when the game starts, then for players joining in progress.
signal member_scene_ready(member: LobbyMember)
## The set of members having the game scene loaded changed (see `is_peer_scene_ready()`).
signal scene_ready_peers_changed
signal invite_received(invite: LobbyInvite)
signal invites_changed
signal friends_changed
signal lobby_list_received(lobbies: Array[LobbyInfo])
## Host: the list of disconnected members whose seat is kept changed (`get_absent_members()`).
signal absent_members_changed

const LOBBY_NAME_KEY: String = "name"
const BACKEND_NAME_KEY: String = "name"
const BACKEND_IN_GAME_KEY: String = "in_game"
const BACKEND_OPEN_KEY: String = "open"

static var _services: Array[LobbyService] = []

var config: LobbyConfig
var backend: LobbyBackend
var scene_loader: LobbySceneLoader
var state: LobbyTypes.State = LobbyTypes.State.NONE
var lobby_id: int = 0
var visibility: LobbyTypes.Visibility = LobbyTypes.Visibility.FRIENDS_ONLY
## Why the last lobby was left or could not be entered. Reset by `create()` and `join()`.
var last_reason: LobbyTypes.Reason = LobbyTypes.Reason.NONE
## Invitations received and not answered yet, most recent first.
var invites: Array[LobbyInvite] = []

## Admitted players, by peer id.
var members: Dictionary[int, LobbyMember]:
	get: return _member_sync.members
var local_member: LobbyMember:
	get: return _member_sync.local_member
var lobby_name: String:
	get: return str(get_lobby_data(LOBBY_NAME_KEY, ""))
## What the backend can do, for the UI to hide the rest.
var supports_friends: bool:
	get: return backend.supports_friends
var supports_invites: bool:
	get: return backend.supports_invites
var supports_invite_overlay: bool:
	get: return backend.supports_invite_overlay
## Keys of member data only the host may write (see `LobbyMemberSync.host_only_keys`).
var host_only_member_keys: Array[String]:
	get: return _member_sync.host_only_keys
	set(value): _member_sync.host_only_keys = value
## Host: optional validation of member data,
## `func(member: LobbyMember, key: String, value: Variant) -> bool`.
var member_data_validator: Callable:
	get: return _member_sync.data_validator
	set(value): _member_sync.data_validator = value

## Voice chat between the members of the lobby.
var voice: VoiceChat
## Debug: makes the connection of this player behave like a bad one (latency, jitter,
## packet loss). Set it before creating or joining a lobby; its values can be changed
## while connected. See SimulatedNetworkPeer.
var network_conditions: NetworkConditions

var _member_sync: LobbyMemberSync
var _scene_sync: LobbySceneSync
var _ping: LobbyPing
## The connection in use when `network_conditions` are simulated, null otherwise.
var _simulated_peer: SimulatedNetworkPeer
## Incremented whenever a create / join attempt starts or ends: invalidates its timeout.
var _attempt: int = 0
## Lobby of the game the local player was disconnected from, 0 when there is none.
var _rejoin_lobby_id: int = 0
var _rejoin_until_msec: int = 0

## Returns the service a node belongs to (the one sharing its multiplayer API).
static func for_node(node: Node) -> LobbyService:
	for service: LobbyService in _services:
		if service.multiplayer == node.multiplayer:
			return service
	return null

## Must be called once, before the service enters the tree. Without a `voice_source`,
## there is no voice chat.
func setup(
	_config: LobbyConfig, _backend: LobbyBackend, _scene_loader: LobbySceneLoader,
	voice_source: VoiceSource = null
) -> void:
	config = _config
	backend = _backend
	scene_loader = _scene_loader
	visibility = config.default_visibility
	backend.name = "Backend"
	backend.setup(config)
	add_child(backend)
	# These two receive RPCs: explicit names keep their paths identical on every peer.
	_member_sync = LobbyMemberSync.new()
	_member_sync.name = "MemberSync"
	_member_sync.setup(config, backend)
	_member_sync.admission_check = _check_admission
	add_child(_member_sync)
	_scene_sync = LobbySceneSync.new()
	_scene_sync.name = "SceneSync"
	_scene_sync.setup(config, _member_sync, scene_loader)
	add_child(_scene_sync)
	_ping = LobbyPing.new()
	_ping.name = "Ping"
	_ping.setup(config, _member_sync)
	_member_sync.seat_policy = _scene_sync.is_game_active
	add_child(_ping)
	voice = VoiceChat.new()
	voice.name = "Voice"
	voice.setup(config, _member_sync, voice_source)
	add_child(voice)
	_connect_signals()

func _enter_tree() -> void:
	_services.append(self)

func _exit_tree() -> void:
	_services.erase(self)

func _ready() -> void:
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Lobby lifecycle ---------------------------------------------------------------------

func is_available() -> bool:
	return backend != null and backend.is_available()

func is_in_lobby() -> bool:
	return state >= LobbyTypes.State.IN_LOBBY

func is_host() -> bool:
	return is_in_lobby() and _member_sync.is_host()

## Creates a lobby. Answers with `created` or `create_failed`.
func create(with_visibility: LobbyTypes.Visibility = config.default_visibility) -> void:
	if not _begin_attempt(LobbyTypes.State.CREATING, create_failed):
		return
	visibility = with_visibility
	backend.create(visibility)

## Joins a lobby, leaving the current one first. Answers with `joined` or `join_failed`.
func join(target_lobby_id: int) -> void:
	if not _begin_attempt(LobbyTypes.State.JOINING, join_failed):
		return
	backend.join(target_lobby_id)

func leave() -> void:
	if state == LobbyTypes.State.NONE:
		return
	# Said before the connection closes, so the others know it is deliberate.
	if is_host():
		_member_sync.announce_closing()
	else:
		_member_sync.announce_departure()
	_rejoin_lobby_id = 0
	_leave(LobbyTypes.Reason.VOLUNTARY)

## True when the local player lost its connection during a game and its seat is still
## kept by the host (`LobbyConfig.reconnect_grace`).
func can_rejoin() -> bool:
	return (
		state == LobbyTypes.State.NONE and _rejoin_lobby_id != 0
		and Time.get_ticks_msec() < _rejoin_until_msec
	)

## Comes back to the game that was lost. Answers like `join()`.
func rejoin() -> void:
	if can_rejoin():
		join(_rejoin_lobby_id)

## Host only. The members who lost their connection during the game and whose seat is
## kept: their name and data, with a peer id of 0.
func get_absent_members() -> Array[LobbyMember]:
	return _member_sync.get_absent_members()

# --- Members -----------------------------------------------------------------------------

func get_member(peer_id: int) -> LobbyMember:
	return _member_sync.get_member(peer_id)

## Members sorted by peer id: the host comes first.
func get_members() -> Array[LobbyMember]:
	var sorted_members: Array[LobbyMember] = []
	sorted_members.assign(members.values())
	sorted_members.sort_custom(
		func(a: LobbyMember, b: LobbyMember) -> bool: return a.peer_id < b.peer_id
	)
	return sorted_members

## Sets a piece of data on the local member, or as the host on any member.
## It is validated by the host then sent to everyone. A null value erases the key.
func set_member_data(key: String, value: Variant, member: LobbyMember = null) -> void:
	_member_sync.set_member_data(key, value, member)

func set_ready(ready: bool) -> void:
	set_member_data(LobbyMember.READY_KEY, ready)

## True when every member except the host is ready.
func are_all_ready() -> bool:
	for member: LobbyMember in members.values():
		if not member.is_host and not member.is_ready:
			return false
	return true

## Host only. Removes a player, who cannot come back until the lobby closes.
func kick(member: LobbyMember) -> void:
	if is_host() and member != null and member != local_member:
		_member_sync.dismiss(member.peer_id, LobbyTypes.Reason.KICKED, true)

# --- Lobby data --------------------------------------------------------------------------

## Host only. Data shared with every member (selected map, game mode...).
func set_lobby_data(key: String, value: Variant) -> void:
	_member_sync.set_lobby_data(key, value)

func get_lobby_data(key: String, default: Variant = null) -> Variant:
	return _member_sync.lobby_data.get(key, default)

## Host only.
func set_visibility(new_visibility: LobbyTypes.Visibility) -> void:
	if not is_host() or new_visibility == visibility:
		return
	visibility = new_visibility
	backend.set_visibility(visibility)
	visibility_changed.emit(visibility)

# --- Game --------------------------------------------------------------------------------

func can_start_game() -> bool:
	if not is_host() or state != LobbyTypes.State.IN_LOBBY:
		return false
	return not config.require_all_ready or are_all_ready()

## Host only. Loads the game scene (`LobbyConfig.game_scene` by default) on every member.
## Returns false when the game cannot start.
func start_game(scene_path: String = "") -> bool:
	if not can_start_game():
		return false
	# The lobby stays enterable for the players allowed to come in during the game: anyone
	# with join in progress, the holders of a reserved seat otherwise. The host decides
	# who is admitted.
	backend.set_joinable(config.allow_join_in_progress or config.reconnect_grace > 0.0)
	backend.set_lobby_data(BACKEND_OPEN_KEY, "1" if config.allow_join_in_progress else "0")
	backend.set_lobby_data(BACKEND_IN_GAME_KEY, "1")
	_scene_sync.order_load(
		scene_path if not scene_path.is_empty() else config.game_scene, LobbyTypes.State.IN_GAME
	)
	return true

## Host only, during the game. Loads another game scene on every member (next level...).
## Returns false when it cannot be done.
func change_game_scene(scene_path: String) -> bool:
	if not is_host() or state != LobbyTypes.State.IN_GAME or scene_path.is_empty():
		return false
	_scene_sync.order_load(scene_path, LobbyTypes.State.IN_GAME)
	return true

## Host only. Brings every member back to the lobby scene.
func return_to_lobby() -> void:
	if not is_host() or state != LobbyTypes.State.IN_GAME:
		return
	for member: LobbyMember in get_members():
		set_member_data(LobbyMember.READY_KEY, null, member)
	# The game is over: nobody has a seat to come back to.
	_member_sync.clear_seats()
	backend.set_joinable(true)
	backend.set_lobby_data(BACKEND_OPEN_KEY, "1")
	backend.set_lobby_data(BACKEND_IN_GAME_KEY, "0")
	_scene_sync.order_load(config.lobby_scene, LobbyTypes.State.IN_LOBBY)

## True when the member has the game scene loaded.
func is_member_scene_ready(member: LobbyMember) -> bool:
	return member != null and _scene_sync.is_peer_ready(member.peer_id)

func is_peer_scene_ready(peer_id: int) -> bool:
	return _scene_sync.is_peer_ready(peer_id)

## Peer ids of the members having the game scene loaded: the only ones that can be sent
## anything about the game scene (RPC on its nodes, replicated objects).
var scene_ready_peers: Array[int]:
	get: return _scene_sync.get_ready_peers()

# --- Friends, invites, lobby list --------------------------------------------------------

func get_friends() -> Array[LobbyUser]:
	return backend.get_friends()

func invite(user_id: int) -> void:
	if is_in_lobby():
		backend.invite(user_id)

func open_invite_overlay() -> void:
	if is_in_lobby():
		backend.open_invite_overlay()

func accept_invite(lobby_invite: LobbyInvite) -> void:
	_remove_invite(lobby_invite)
	join(lobby_invite.lobby_id)

func decline_invite(lobby_invite: LobbyInvite) -> void:
	_remove_invite(lobby_invite)

## Answers with `lobby_list_received`.
func request_lobby_list() -> void:
	backend.request_lobby_list()

# --- Internals ---------------------------------------------------------------------------

func _connect_signals() -> void:
	backend.lobby_created.connect(_on_backend_lobby_created)
	backend.lobby_create_failed.connect(_on_backend_lobby_create_failed)
	backend.lobby_joined.connect(_on_backend_lobby_joined)
	backend.lobby_join_failed.connect(_on_backend_lobby_join_failed)
	backend.lobby_closed.connect(_on_backend_lobby_closed)
	backend.join_requested.connect(join)
	backend.invite_received.connect(_on_backend_invite_received)
	backend.friends_changed.connect(friends_changed.emit)
	backend.lobby_list_received.connect(_on_backend_lobby_list_received)
	_member_sync.member_added.connect(member_joined.emit)
	_member_sync.member_removed.connect(member_left.emit)
	_member_sync.member_updated.connect(member_updated.emit)
	_member_sync.lobby_data_changed.connect(lobby_data_changed.emit)
	_member_sync.admitted.connect(_on_admitted)
	_member_sync.dismissed.connect(_on_dismissed)
	_member_sync.seats_changed.connect(absent_members_changed.emit)
	_ping.member_unreachable.connect(_member_sync.drop)
	_ping.host_unreachable.connect(_end_later.bind(LobbyTypes.Reason.CONNECTION_LOST))
	_scene_sync.load_started.connect(_on_scene_load_started)
	_scene_sync.completed.connect(_on_scene_completed)
	_scene_sync.peer_ready.connect(_on_scene_peer_ready)
	_scene_sync.ready_peers_changed.connect(scene_ready_peers_changed.emit)
	_scene_sync.load_failed.connect(_end_later.bind(LobbyTypes.Reason.LOAD_FAILED))

func _set_state(new_state: LobbyTypes.State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

## Common start of create() and join(). Returns false when the attempt cannot start.
func _begin_attempt(attempt_state: LobbyTypes.State, failure: Signal) -> bool:
	if state != LobbyTypes.State.NONE:
		var rejoin_lobby_id: int = _rejoin_lobby_id
		leave()
		_rejoin_lobby_id = rejoin_lobby_id
	last_reason = LobbyTypes.Reason.NONE
	if not is_available():
		last_reason = LobbyTypes.Reason.BACKEND_UNAVAILABLE
		failure.emit.call_deferred(last_reason)
		return false
	_attempt += 1
	get_tree().create_timer(config.join_timeout).timeout.connect(_on_attempt_timeout.bind(_attempt))
	_set_state(attempt_state)
	return true

func _on_attempt_timeout(attempt: int) -> void:
	if attempt == _attempt:
		_end(LobbyTypes.Reason.TIMEOUT)

## Ends whatever is going on (attempt or lobby) and reports it with the right signal.
func _end(reason: LobbyTypes.Reason) -> void:
	match state:
		LobbyTypes.State.NONE:
			return
		LobbyTypes.State.CREATING:
			_teardown(reason)
			create_failed.emit(reason)
		LobbyTypes.State.JOINING:
			_teardown(reason)
			join_failed.emit(reason)
		_:
			_leave(reason)

func _leave(reason: LobbyTypes.Reason) -> void:
	_teardown(reason)
	left.emit(reason)

## Same as `_end()`, once the current network callback returned: closing the connection
## from inside one of its own callbacks is not safe.
func _end_later(reason: LobbyTypes.Reason) -> void:
	var attempt: int = _attempt
	(func() -> void:
		if attempt == _attempt:
			_end(reason)
	).call_deferred()

func _teardown(reason: LobbyTypes.Reason) -> void:
	_attempt += 1
	last_reason = reason
	if reason == LobbyTypes.Reason.CONNECTION_LOST and _scene_sync.is_game_active() and config.reconnect_grace > 0.0:
		# The host keeps the seat for that long: remember where to come back.
		_rejoin_lobby_id = lobby_id
		_rejoin_until_msec = Time.get_ticks_msec() + roundi(config.reconnect_grace * 1000.0)
	lobby_id = 0
	# The connection goes first: the resets below make the game scene stop replicating,
	# which must not be attempted on a connection that is already dead.
	if _simulated_peer != null:
		# What was sent just before leaving (a goodbye) must not stay in the simulation.
		_simulated_peer.flush()
		_simulated_peer = null
	backend.leave()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_scene_sync.reset()
	_member_sync.reset()
	_set_state(LobbyTypes.State.NONE)

## Makes the connection of the backend the one of the multiplayer API.
func _install_connection() -> void:
	var peer: MultiplayerPeer = backend.get_peer()
	_simulated_peer = null
	if network_conditions != null and peer != null:
		_simulated_peer = SimulatedNetworkPeer.new(peer, network_conditions)
		peer = _simulated_peer
	multiplayer.multiplayer_peer = peer

func _check_admission(_user_id: int, has_seat: bool) -> LobbyTypes.Reason:
	# A player coming back to its seat is always let in.
	if _scene_sync.is_game_active() and not config.allow_join_in_progress and not has_seat:
		return LobbyTypes.Reason.GAME_IN_PROGRESS
	return LobbyTypes.Reason.NONE

func _remove_invite(lobby_invite: LobbyInvite) -> void:
	if invites.has(lobby_invite):
		invites.erase(lobby_invite)
		invites_changed.emit()

func _on_backend_lobby_created(new_lobby_id: int) -> void:
	if state != LobbyTypes.State.CREATING:
		return
	_attempt += 1
	_rejoin_lobby_id = 0
	lobby_id = new_lobby_id
	_install_connection()
	_member_sync.start_host()
	var new_lobby_name: String = "%s's lobby" % local_member.name
	set_lobby_data(LOBBY_NAME_KEY, new_lobby_name)
	backend.set_lobby_data(BACKEND_NAME_KEY, new_lobby_name)
	backend.set_lobby_data(BACKEND_IN_GAME_KEY, "0")
	backend.set_lobby_data(BACKEND_OPEN_KEY, "1")
	_set_state(LobbyTypes.State.IN_LOBBY)
	created.emit()
	entered.emit()

func _on_backend_lobby_create_failed(reason: LobbyTypes.Reason) -> void:
	if state == LobbyTypes.State.CREATING:
		_end(reason)

func _on_backend_lobby_joined(joined_lobby_id: int) -> void:
	if state != LobbyTypes.State.JOINING:
		return
	lobby_id = joined_lobby_id
	# The member registry introduces the local player to the host once connected.
	_install_connection()

func _on_backend_lobby_join_failed(reason: LobbyTypes.Reason) -> void:
	if state == LobbyTypes.State.JOINING:
		_end(reason)

func _on_backend_lobby_closed(reason: LobbyTypes.Reason) -> void:
	_end_later(reason)

func _on_admitted() -> void:
	if state != LobbyTypes.State.JOINING:
		return
	_attempt += 1
	_rejoin_lobby_id = 0
	_set_state(LobbyTypes.State.IN_LOBBY)
	joined.emit()
	entered.emit()

func _on_dismissed(reason: LobbyTypes.Reason) -> void:
	_end_later(reason)

func _on_connection_failed() -> void:
	_end_later(LobbyTypes.Reason.CONNECTION_FAILED)

func _on_server_disconnected() -> void:
	# A host that leaves on purpose says so first (see `leave()`): without that notice,
	# the connection was lost.
	if state == LobbyTypes.State.JOINING:
		_end_later(LobbyTypes.Reason.CONNECTION_FAILED)
	else:
		_end_later(LobbyTypes.Reason.CONNECTION_LOST)

func _on_scene_load_started(_path: String, _target_state: LobbyTypes.State) -> void:
	_set_state(LobbyTypes.State.LOADING)

func _on_scene_completed(target_state: LobbyTypes.State) -> void:
	_set_state(target_state)
	if target_state == LobbyTypes.State.IN_GAME:
		game_started.emit()

func _on_scene_peer_ready(peer_id: int) -> void:
	var member: LobbyMember = get_member(peer_id)
	if member != null and state == LobbyTypes.State.IN_GAME:
		member_scene_ready.emit(member)

func _on_backend_invite_received(lobby_invite: LobbyInvite) -> void:
	for existing: LobbyInvite in invites:
		if existing.lobby_id == lobby_invite.lobby_id and existing.from.id == lobby_invite.from.id:
			return
	invites.push_front(lobby_invite)
	invites_changed.emit()
	invite_received.emit(lobby_invite)

func _on_backend_lobby_list_received(lobbies: Array[LobbyInfo]) -> void:
	lobby_list_received.emit(lobbies)
