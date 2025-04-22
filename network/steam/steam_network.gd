class_name SteamNetwork
extends Node

const PACKET_READ_LIMIT: int = 32
var lobby: SteamLobby = null

func _init(_lobby: SteamLobby) -> void:
	lobby = _lobby

func _ready() -> void:
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(_delta: float) -> void:
	if lobby.id > 0:
		read_p2p_packets()

func _on_p2p_session_request(user_id: int):
	var requester: String = Steam.getFriendPersonaName(user_id)
	Steam.acceptP2PSessionWithUser(user_id)

func send_p2p_packet(data: Dictionary, target: SteamUser = null, reliable: bool = false) -> void:
	const channel: int = 0
	var packed_data: PackedByteArray = var_to_bytes(data)
	if target == null: # send to everyone
		for member in lobby.members:
			if member.id == lobby.active_member.id:
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
	var data: Dictionary = bytes_to_var(packet.get("data"))
	print(data)
	var message: String = data.get("message")
	if message:
		match message:
			"USER_JOINED":
				var user: SteamUser = data.get("user")
				lobby.refresh_members()
