class_name SteamNetwork
extends Node

enum SEND_TYPE {
	UNRELIABLE,
	UNRELIABLE_NO_DELAY,
	RELIABLE,
	RELIABLE_WITH_BUFFERING
}

const PACKET_READ_LIMIT: int = 32
var lobby: SteamLobby = null

func _init(_lobby: SteamLobby) -> void:
	lobby = _lobby

func _ready() -> void:
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(_delta: float) -> void:
	if lobby.id == 0:
		return
	read_p2p_packets()

func send_p2p_packet(data: Dictionary, target: SteamUser = null, type: SEND_TYPE = SEND_TYPE.RELIABLE) -> void:
	const channel: int = 0
	var packed_data: PackedByteArray = var_to_bytes(data)
	if target == null: # send to everyone
		for member in lobby.members:
			if member.id == lobby.local_member.id:
				continue
			Steam.sendP2PPacket(member.id, packed_data, type, channel)
	else:
		Steam.sendP2PPacket(target.id, packed_data, type, channel)

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
	var message: String = data.get("message")
	if message:
		match message:
			"LOBBY_USER_JOINED":
				lobby.refresh_members()

func close_connection(user: SteamUser) -> void:
	if user.id == SteamManager.user.id:
		return
	var session_state: Dictionary = Steam.getP2PSessionState(user.id)
	if !session_state.has("connection_active") || !session_state["connection_active"]:
		return
	Steam.closeP2PSessionWithUser(user.id)

func _on_p2p_session_request(user_id: int):
	Steam.acceptP2PSessionWithUser(user_id)
