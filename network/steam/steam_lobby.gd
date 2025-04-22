class_name SteamLobby
extends Node

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
	auto_join()

func _exit_tree():
	leave()

func auto_join() -> void:
	var args: Array = OS.get_cmdline_args()
	if args.size() == 0: 
		return
	if args[0] != "+connect_lobby" || int(args[1]) == 0:
		return
	join(int(args[1]))

func create() -> void:
	if id == 0:
		local_member.is_host = true
		Steam.createLobby(Steam.LOBBY_TYPE_PRIVATE, max_members)

func join(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)

func leave() -> void:
	if id == 0:
		return
	Steam.leaveLobby(id)
	for member in members:
		if member.id == local_member.id:
			continue
		var session_state: Dictionary = Steam.getP2PSessionState(member.id)
		if !session_state.has("connection_active") || !session_state["connection_active"]:
			continue
		Steam.closeP2PSessionWithUser(member.id)
	id = 0
	members.clear()

func invite(user: SteamUser) -> void:
	Steam.inviteUserToLobby(id, user.id)

func refresh_members() -> void:
	members.clear()
	var members_count: int = Steam.getNumLobbyMembers(id)
	for member_index in range(0, members_count):
		var user_id: int = Steam.getLobbyMemberByIndex(id, member_index)
		var username: String = Steam.getFriendPersonaName(user_id)
		members.append(SteamUser.new(user_id, username))
		print("username ", username)

func _on_created(connect: int, lobby_id: int) -> void:
	if connect == 1:
		id = lobby_id
		Steam.setLobbyJoinable(id, true)
		Steam.allowP2PPacketRelay(true)
		lobby_name = "%s's lobby" % local_member.name
		Steam.setLobbyData(id, "name", lobby_name)
		refresh_members()
		print("lobby id ", lobby_id)

func _on_joined(lobby_id: int, permissions: int, locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS: 
		return
	id = lobby_id
	network.send_p2p_packet({
		"message": "LOBBY_USER_JOINED", 
		"user": local_member
	})
	refresh_members()
