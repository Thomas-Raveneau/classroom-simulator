class_name SteamLobby
extends Node

const PACKET_READ_LIMIT: int = 32

var id: int = 0
var lobby_name: String = ""
var active_member: SteamUser
var members: Array[SteamUser] = []
var max_members: int = 10

func _init(_active_member: SteamUser) -> void:
	active_member = _active_member

func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(_delta: float) -> void:
	if id > 0:
		read_p2p_packets()

func create() -> void:
	if id == 0:
		active_member.is_host = true
		Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_members)

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
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		id = lobby_id
		refresh_members()
		make_p2p_handshake()

func refresh_members() -> void:
	members.clear()
	var members_count: int = Steam.getNumLobbyMembers(id)
	for member_index in range(0, members_count):
		var user_id: int = Steam.getLobbyMemberByIndex(id, member_index)
		var username: String = Steam.getFriendPersonaName(user_id)
		members.append(SteamUser.new(user_id, username))
		print("username ", username)

func _on_p2p_session_request(user_id: int):
	var requester: String = Steam.getFriendPersonaName(user_id)
	Steam.acceptP2PSessionWithUser(user_id)

func make_p2p_handshake() -> void:
	var data: Dictionary = {
		"message": "handshake",
		"user": active_member,
	}
	send_p2p_packet(data)

func send_p2p_packet(data: Dictionary, target: SteamUser = null, reliable: bool = false) -> void:
	const channel: int = 0
	var packed_data: PackedByteArray = var_to_bytes(data)
	if target == null: # send to everyone
		for member in members:
			if member.id == active_member.id:
				continue
			Steam.sendP2PPacket(member.id, packed_data, channel)
	else:
		Steam.sendP2PPacket(target.id, packed_data, channel)

func read_p2p_packets(read_count: int = 0) -> void:
	if read_count >= PACKET_READ_LIMIT:
		return
	const channel: int = 0
	if Steam.getAvailableP2PPacketSize(channel) > 0:
		read_p2p_packet()
		read_p2p_packets(read_count + 1)

func read_p2p_packet() -> void:
	const channel: int = 0
	var available_packet_size: int = Steam.getAvailableP2PPacketSize(channel)
	if available_packet_size == 0:
		return
	var packet: Dictionary = Steam.readP2PPacket(available_packet_size, channel)
	var sender: int = packet.get('user_id')
	var data: Dictionary = bytes_to_var(packet.get('data'))
	var message: String = data.get["message"]
	if message:
		match message:
			"handshake":
				var user: SteamUser = data.get("user")
				refresh_members()
