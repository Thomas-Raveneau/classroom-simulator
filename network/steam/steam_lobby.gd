class_name SteamLobby
extends Node

var id: int = 0
var lobby_name: String = ""
var active_member: SteamUser
var members: Array[SteamUser] = []
var max_members: int = 10
var network: SteamNetwork

func _init(_active_member: SteamUser) -> void:
	active_member = _active_member

func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)

func create() -> void:
	if id == 0:
		active_member.is_host = true
		Steam.createLobby(Steam.LOBBY_TYPE_PRIVATE, max_members)

func _on_lobby_created(connect: int, lobby_id: int) -> void:
	if connect == 1:
		id = lobby_id
		Steam.setLobbyJoinable(id, true)
		lobby_name = "%s's lobby" % active_member.name
		Steam.setLobbyData(id, "name", lobby_name)
		refresh_members()
		print("lobby id ", lobby_id)

func join_lobby(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)

func _on_lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS: 
		return
	id = lobby_id
	network.send_p2p_packet({
		"message": "USER_JOINED", 
		"user": active_member
	})
	refresh_members()

func refresh_members() -> void:
	members.clear()
	var members_count: int = Steam.getNumLobbyMembers(id)
	for member_index in range(0, members_count):
		var user_id: int = Steam.getLobbyMemberByIndex(id, member_index)
		var username: String = Steam.getFriendPersonaName(user_id)
		members.append(SteamUser.new(user_id, username))
		print("username ", username)
