class_name SteamLobby
extends Node

signal on_created
signal on_lobby_joined
signal on_members_refreshed
signal on_invite_received(user: SteamUser, lobby_id: int)

var id: int = 0
var lobby_name: String = ""
var members: Array[SteamUser] = []

func _ready() -> void:
	Steam.lobby_invite.connect(_on_invite_received)
	Steam.lobby_joined.connect(_on_joined)
	NetworkManager.peer.lobby_created.connect(_on_created)
	NetworkManager.peer.lobby_chat_update.connect(_on_member_update)
	NetworkManager.peer.lobby_data_update.connect(_on_lobby_update)
	auto_join()

func create() -> void:
	if id != 0:
		return
	NetworkManager.steam.user.is_host = true
	var error = NetworkManager.peer.create_lobby(
		SteamMultiplayerPeer.LOBBY_TYPE_FRIENDS_ONLY, 
		GameSettings.MAX_PLAYERS
	)

func join(lobby_id: int) -> void:
	NetworkManager.peer.connect_lobby(lobby_id)

func auto_join() -> void:
	var args: Array = OS.get_cmdline_args()
	if args.size() == 0: 
		return
	if args[0] != "+connect_lobby" || int(args[1]) == 0:
		return
	join(int(args[1]))

func leave() -> void:
	if id == 0:
		return
	if NetworkManager.steam.user.is_host && members.size() > 1:
		var new_host_index: int = members.find_custom(
			func (member):
				return member.id != NetworkManager.steam.user.id
		)
		var new_host: SteamUser = members[new_host_index]
		Steam.setLobbyOwner(id, new_host.id)
	Steam.leaveLobby(id)
	for member in members:
		NetworkManager.steam.network.close_session(member)
	NetworkManager.peer = SteamMultiplayerPeer.new()
	id = 0
	lobby_name = ""
	members.clear()

func set_private(private: bool) -> void:
	if !NetworkManager.steam.user.is_host:
		return
	if private:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_PRIVATE)
	else:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_FRIENDS_ONLY)

func invite(user: SteamUser) -> void:
	var success: bool = Steam.inviteUserToLobby(id, user.id)
	if (!success):
		printerr("Invitation was not successful")

func refresh_members() -> void:
	members.clear()
	var host_id: int = Steam.getLobbyOwner(id)
	var members_count: int = Steam.getNumLobbyMembers(id)
	for member_index in range(0, members_count):
		var member_id: int = Steam.getLobbyMemberByIndex(id, member_index)
		var member_name: String = Steam.getFriendPersonaName(member_id)
		var member = SteamUser.new(member_id, member_name, null, member_id == host_id)
		members.append(member)
	on_members_refreshed.emit()

func _on_created(lobby_connect: int, lobby_id: int) -> void:
	if lobby_connect != 1:
		return
	id = lobby_id
	NetworkManager.set_multiplayer_peer()
	lobby_name = "%s's lobby" % NetworkManager.steam.user.name
	Steam.setLobbyData(id, "name", lobby_name)
	refresh_members()
	on_created.emit()

func _on_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS || id != 0:
		return
	id = lobby_id
	NetworkManager.set_multiplayer_peer()
	refresh_members()
	on_lobby_joined.emit()

func _on_invite_received(user_id: int, lobby_id: int, _game_id: int) -> void:
	var user: SteamUser = SteamUser.new(user_id)
	on_invite_received.emit(user, lobby_id)

func _on_member_update(_lobby_id: int, _user_id: int, _making_change_id: int, status: int) -> void:
	const lobby_updated_status: Array = [
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED,
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT,
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED,
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED
	]
	if (lobby_updated_status.has(status)):
		refresh_members()

func _on_lobby_update(success: int, _lobby_id: int, _user_id: int) -> void:
	if !success || id == 0:
		return
	var owner_id: int = Steam.getLobbyOwner(id)
	if owner_id == NetworkManager.steam.user.id && !NetworkManager.steam.user.is_host:
		NetworkManager.steam.user.is_host = true
		lobby_name = "%s's lobby" %  NetworkManager.steam.user.name
		Steam.setLobbyData(id, "name", lobby_name)
		return
	lobby_name = Steam.getLobbyData(id, "name")
	refresh_members()
