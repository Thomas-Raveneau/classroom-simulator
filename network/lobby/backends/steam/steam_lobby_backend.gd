extends LobbyBackend
## Steam backend: Steam lobbies for discovery, invites and friends, and a
## SteamMultiplayerPeer bound to the lobby for the network transport.
##
## Needs the GodotSteam extension. It has no global class name on purpose: it is loaded
## by path, so the rest of the game still loads when GodotSteam is missing.

const SteamService = preload("steam_service.gd")
const SteamFriends = preload("steam_friends.gd")

## Keys of the Steam lobby data, readable from outside the lobby.
const KEY_GAME: String = "game_key"
const KEY_PROTOCOL: String = "protocol_version"
const KEY_HOST: String = "host_id"
const KEY_NAME: String = "name"
const KEY_IN_GAME: String = "in_game"
const KEY_OPEN: String = "open"
## Passed by Steam when the game is launched from an invitation: `+connect_lobby <id>`.
const CONNECT_ARGUMENT: String = "+connect_lobby"

enum Pending { NONE, CREATING, JOINING }

var _service: SteamService
var _friends: SteamFriends
var _peer: SteamMultiplayerPeer
var _lobby_id: int = 0
var _host_steam_id: int = 0
var _pending: Pending = Pending.NONE
var _pending_lobby_id: int = 0
## Friends' lobbies whose data was asked to Steam for the current lobby list.
var _listed_lobbies: Dictionary[int, LobbyInfo] = {}
var _awaited_lobby_ids: Array[int] = []

func setup(_config: LobbyConfig) -> void:
	super(_config)
	_service = SteamService.new()
	_service.name = "SteamService"
	add_child(_service)
	if not _service.start(config.steam_app_id):
		return
	supports_friends = true
	supports_invites = true
	supports_invite_overlay = true
	_friends = SteamFriends.new()
	_friends.name = "SteamFriends"
	_friends.setup(config.steam_app_id)
	_friends.changed.connect(friends_changed.emit)
	add_child(_friends)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_data_update.connect(_on_lobby_data_update)

func _ready() -> void:
	if is_available():
		_join_lobby_of_launch_arguments()

func is_available() -> bool:
	return _service != null and _service.is_running

func get_backend_name() -> String:
	return "steam"

# --- Lobby -------------------------------------------------------------------------------

func create(visibility: LobbyTypes.Visibility) -> void:
	if not is_available():
		_emit_deferred(lobby_create_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)
		return
	leave()
	_pending = Pending.CREATING
	Steam.createLobby(_to_lobby_type(visibility), config.max_players)

func join(lobby_id: int) -> void:
	if not is_available():
		_emit_deferred(lobby_join_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)
		return
	leave()
	_pending = Pending.JOINING
	_pending_lobby_id = lobby_id
	Steam.joinLobby(lobby_id)

func leave() -> void:
	_pending = Pending.NONE
	_pending_lobby_id = 0
	_host_steam_id = 0
	if _lobby_id != 0:
		Steam.leaveLobby(_lobby_id)
		_lobby_id = 0
	if _peer != null:
		_peer.close()
		_peer = null

func get_peer() -> MultiplayerPeer:
	return _peer

func get_local_identity() -> Dictionary:
	return { "user_id": Steam.getSteamID(), "name": Steam.getPersonaName() }

func resolve_identity(peer_id: int, claim: Dictionary) -> Dictionary:
	# The transport knows which Steam user is behind a peer: what the peer says is ignored.
	var steam_id: int = _peer.get_steam_id_for_peer_id(peer_id) if _peer != null else 0
	if steam_id == 0:
		# Not expected. Fall back on the claim, accepted only for a member of the Steam lobby.
		var claimed_id: Variant = claim.get("user_id")
		if claimed_id is not int or not _is_lobby_member(claimed_id):
			return {}
		push_warning("Steam: no Steam ID for peer %d, using the one it claims." % peer_id)
		steam_id = claimed_id
	return { "user_id": steam_id, "name": Steam.getFriendPersonaName(steam_id) }

func set_joinable(joinable: bool) -> void:
	if _lobby_id == 0:
		return
	Steam.setLobbyJoinable(_lobby_id, joinable)

func set_visibility(visibility: LobbyTypes.Visibility) -> void:
	if _lobby_id != 0:
		Steam.setLobbyType(_lobby_id, _to_lobby_type(visibility))

func set_lobby_data(key: String, value: String) -> void:
	if _lobby_id != 0:
		Steam.setLobbyData(_lobby_id, key, value)

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if _pending != Pending.CREATING:
		# Answer to an attempt given up in the meantime.
		if result == Steam.RESULT_OK:
			Steam.leaveLobby(lobby_id)
		return
	_pending = Pending.NONE
	if result != Steam.RESULT_OK:
		lobby_create_failed.emit(_reason_of_result(result))
		return
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: Error = peer.host_with_lobby(lobby_id) as Error
	if error != OK:
		push_error("Steam: cannot host with lobby %d: %s" % [lobby_id, error_string(error)])
		Steam.leaveLobby(lobby_id)
		lobby_create_failed.emit(LobbyTypes.Reason.BACKEND_ERROR)
		return
	_lobby_id = lobby_id
	_peer = peer
	_host_steam_id = Steam.getSteamID()
	Steam.setLobbyData(lobby_id, KEY_GAME, config.game_key)
	Steam.setLobbyData(lobby_id, KEY_PROTOCOL, str(config.protocol_version))
	Steam.setLobbyData(lobby_id, KEY_HOST, str(_host_steam_id))
	lobby_created.emit(lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if _pending != Pending.JOINING or lobby_id != _pending_lobby_id:
		# Steam also reports the creator entering its own lobby: handled by _on_lobby_created.
		var is_own_lobby: bool = _pending == Pending.CREATING or lobby_id == _lobby_id
		if not is_own_lobby and response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
			Steam.leaveLobby(lobby_id)
		return
	_pending = Pending.NONE
	_pending_lobby_id = 0
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_join_failed.emit(_reason_of_enter_response(response, lobby_id))
		return
	var reason: LobbyTypes.Reason = _check_joined_lobby(lobby_id)
	if reason != LobbyTypes.Reason.NONE:
		Steam.leaveLobby(lobby_id)
		lobby_join_failed.emit(reason)
		return
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: Error = peer.connect_to_lobby(lobby_id) as Error
	if error != OK:
		push_error("Steam: cannot connect to lobby %d: %s" % [lobby_id, error_string(error)])
		Steam.leaveLobby(lobby_id)
		lobby_join_failed.emit(LobbyTypes.Reason.CONNECTION_FAILED)
		return
	_lobby_id = lobby_id
	_peer = peer
	_host_steam_id = Steam.getLobbyOwner(lobby_id)
	lobby_joined.emit(lobby_id)

## Refuses a lobby of another game or version, and a lobby abandoned by its host:
## Steam gives a lobby to another member when its owner leaves, so a lobby can outlive
## the game session it was created for.
func _check_joined_lobby(lobby_id: int) -> LobbyTypes.Reason:
	if Steam.getLobbyData(lobby_id, KEY_GAME) != config.game_key:
		return LobbyTypes.Reason.VERSION_MISMATCH
	if Steam.getLobbyData(lobby_id, KEY_PROTOCOL) != str(config.protocol_version):
		return LobbyTypes.Reason.VERSION_MISMATCH
	if Steam.getLobbyData(lobby_id, KEY_HOST) != str(Steam.getLobbyOwner(lobby_id)):
		return LobbyTypes.Reason.NOT_FOUND
	return LobbyTypes.Reason.NONE

func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if lobby_id != _lobby_id or _host_steam_id == Steam.getSteamID():
		return
	# For a client: the lobby is over as soon as its host is gone, even if the network
	# connection did not notice yet.
	var is_gone: bool = chat_state != Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED
	if (changed_id == _host_steam_id and is_gone) or Steam.getLobbyOwner(lobby_id) != _host_steam_id:
		lobby_closed.emit(LobbyTypes.Reason.HOST_LEFT)

func _join_lobby_of_launch_arguments() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	var index: int = arguments.find(CONNECT_ARGUMENT)
	if index == -1 or index + 1 >= arguments.size():
		return
	var lobby_id: int = arguments[index + 1].to_int()
	if lobby_id == 0:
		return
	# Once the game has finished starting.
	await get_tree().process_frame
	await get_tree().process_frame
	join_requested.emit(lobby_id)

# --- Friends and invites -----------------------------------------------------------------

func get_friends() -> Array[LobbyUser]:
	return _friends.get_friends() if _friends != null else []

func invite(user_id: int) -> void:
	if _lobby_id != 0 and not Steam.inviteUserToLobby(_lobby_id, user_id):
		push_warning("Steam: the invitation to %d could not be sent." % user_id)

func open_invite_overlay() -> void:
	if _lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(_lobby_id)

func _on_lobby_invite(inviter_id: int, lobby_id: int, game_id: int) -> void:
	if game_id != config.steam_app_id:
		return
	var inviter: LobbyUser = LobbyUser.new(inviter_id, Steam.getFriendPersonaName(inviter_id), lobby_id)
	invite_received.emit(LobbyInvite.new(inviter, lobby_id))

## The user accepted an invitation or clicked "Join game" in the Steam overlay or friends list.
func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_requested.emit(lobby_id)

# --- Lobby list --------------------------------------------------------------------------

## Public lobbies of this game, plus the lobbies where friends sit (which Steam does not
## return in a search when they are friends-only). Friends' lobbies arrive one by one:
## `lobby_list_received` is emitted again each time the list grows.
func request_lobby_list() -> void:
	if not is_available():
		super()
		return
	_listed_lobbies.clear()
	_awaited_lobby_ids = _friends.get_lobby_ids()
	for lobby_id: int in _awaited_lobby_ids:
		Steam.requestLobbyData(lobby_id)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter(KEY_GAME, config.game_key, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobby_ids: Array) -> void:
	for lobby_id: Variant in lobby_ids:
		if lobby_id is int:
			_list_lobby(lobby_id, false)
	_emit_lobby_list()

func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int) -> void:
	if not _awaited_lobby_ids.has(lobby_id):
		return
	_awaited_lobby_ids.erase(lobby_id)
	if success != 0 and _list_lobby(lobby_id, true):
		_emit_lobby_list()

## Adds a lobby to the current list. Returns false when it is not a lobby to show.
func _list_lobby(lobby_id: int, has_friend: bool) -> bool:
	if lobby_id == _lobby_id:
		return false
	if Steam.getLobbyData(lobby_id, KEY_GAME) != config.game_key:
		return false
	if Steam.getLobbyData(lobby_id, KEY_PROTOCOL) != str(config.protocol_version):
		return false
	var info: LobbyInfo = _listed_lobbies.get(lobby_id)
	if info == null:
		info = LobbyInfo.new(lobby_id)
		_listed_lobbies[lobby_id] = info
	info.name = Steam.getLobbyData(lobby_id, KEY_NAME)
	info.member_count = Steam.getNumLobbyMembers(lobby_id)
	info.max_members = Steam.getLobbyMemberLimit(lobby_id)
	info.in_game = Steam.getLobbyData(lobby_id, KEY_IN_GAME) == "1"
	info.is_open = Steam.getLobbyData(lobby_id, KEY_OPEN) != "0"
	info.has_friend = info.has_friend or has_friend or _friends.get_lobby_ids().has(lobby_id)
	return true

func _emit_lobby_list() -> void:
	var lobbies: Array[LobbyInfo] = []
	lobbies.assign(_listed_lobbies.values())
	# Friends first, then by name.
	lobbies.sort_custom(
		func(a: LobbyInfo, b: LobbyInfo) -> bool:
			if a.has_friend != b.has_friend:
				return a.has_friend
			return a.name.naturalnocasecmp_to(b.name) < 0
	)
	lobby_list_received.emit(lobbies)

# --- Helpers -----------------------------------------------------------------------------

func _is_lobby_member(steam_id: int) -> bool:
	for index: int in Steam.getNumLobbyMembers(_lobby_id):
		if Steam.getLobbyMemberByIndex(_lobby_id, index) == steam_id:
			return true
	return false

func _to_lobby_type(visibility: LobbyTypes.Visibility) -> int:
	match visibility:
		LobbyTypes.Visibility.PRIVATE: return Steam.LOBBY_TYPE_PRIVATE
		LobbyTypes.Visibility.PUBLIC: return Steam.LOBBY_TYPE_PUBLIC
		_: return Steam.LOBBY_TYPE_FRIENDS_ONLY

func _reason_of_result(result: int) -> LobbyTypes.Reason:
	match result:
		Steam.RESULT_TIMEOUT: return LobbyTypes.Reason.TIMEOUT
		Steam.RESULT_NO_CONNECTION: return LobbyTypes.Reason.BACKEND_UNAVAILABLE
		_: return LobbyTypes.Reason.BACKEND_ERROR

func _reason_of_enter_response(response: int, lobby_id: int) -> LobbyTypes.Reason:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
			return LobbyTypes.Reason.NOT_FOUND
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
			return LobbyTypes.Reason.LOBBY_FULL
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
			# A lobby locked for the duration of the game answers "not allowed".
			if Steam.getLobbyData(lobby_id, KEY_IN_GAME) == "1":
				return LobbyTypes.Reason.GAME_IN_PROGRESS
	return LobbyTypes.Reason.CONNECTION_FAILED
