class_name SteamLobby
extends Node

signal on_created
signal on_members_refreshed

var id: int = 0
var lobby_name: String = ""
var local_member: SteamUser
var members: Array[SteamUser] = []
var max_members: int = 10
var network: SteamNetwork

func _init(_local_member: SteamUser) -> void:
	local_member = _local_member

func _ready() -> void:
	Steam.lobby_created.connect(_on_created)
	Steam.lobby_joined.connect(_on_joined)
	Steam.lobby_invite.connect(_on_invite)
	Steam.lobby_chat_update.connect(_on_update)
	auto_join()

func create() -> void:
	if id != 0:
		return
	local_member.is_host = true
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_members)

func set_private(private: bool) -> void:
	if !SteamManager.user.is_host:
		return
	if private:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_PRIVATE)
	else:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_FRIENDS_ONLY)

func join(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)

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
	Steam.leaveLobby(id)
	for member in members:
		network.close_connection(member)
	id = 0
	members.clear()

func invite(user: SteamUser) -> void:
	var success: bool = Steam.inviteUserToLobby(id, user.id)
	if (!success):
		print("Invitation was not successful")

func refresh_members() -> void:
	members.clear()
	var members_count: int = Steam.getNumLobbyMembers(id)
	for member_index in range(0, members_count):
		var user_id: int = Steam.getLobbyMemberByIndex(id, member_index)
		var username: String = Steam.getFriendPersonaName(user_id)
		var game_info: Dictionary = Steam.getFriendGamePlayed(user_id) 
		members.append(SteamUser.new(user_id, username))
	on_members_refreshed.emit()

func _on_created(lobby_connect: int, lobby_id: int) -> void:
	if lobby_connect != 1:
		return
	id = lobby_id
	Steam.setLobbyJoinable(id, true)
	Steam.allowP2PPacketRelay(true)
	lobby_name = "%s's lobby" % local_member.name
	Steam.setLobbyData(id, "name", lobby_name)
	refresh_members()
	on_created.emit()

func _on_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS: 
		return
	id = lobby_id
	refresh_members()

func _on_invite(_user_id: int, lobby_id: int, _game_id: int) -> void:
	join(lobby_id)

func _on_update(_lobby_id: int, _user_id: int, _making_change_id: int, status: int) -> void:
	const lobby_updated_status: Array = [
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED,
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT,
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED,
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED
	]
	if (lobby_updated_status.has(status)):
		refresh_members()
	else:
		printerr("Not handled update")
