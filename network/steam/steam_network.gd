class_name SteamNetwork
extends Node

enum send_type {
	UNRELIABLE = Steam.NETWORKING_SEND_UNRELIABLE,
	NO_NAGLE = Steam.NETWORKING_SEND_NO_NAGLE,
	UNRELIABLE_NO_NAGLE = Steam.NETWORKING_SEND_URELIABLE_NO_NAGLE,
	NO_DELAY = Steam.NETWORKING_SEND_NO_DELAY,
	UNRELIABLE_NO_DELAY = Steam.NETWORKING_SEND_UNRELIABLE_NO_DELAY,
	RELIABLE = Steam.NETWORKING_SEND_RELIABLE,
	RELIABLE_NO_NAGLE = Steam.NETWORKING_SEND_RELIABLE_NO_NAGLE
}

enum session_state {
	NONE = 0,
	CONNECTING = 1,
	FINDING_ROUTE = 2,
	CONNECTED = 3,
	CLOSED_BY_PEER = 4,
	LOCAL_PROBLEM = 5,
	WAIT = -1,
	LINGER = -2,
	DEAD = -3
}

const CHANNEL: int = 50
const MAX_MESSAGES: int = 10

func _ready() -> void:
	Steam.network_messages_session_request.connect(_on_session_request)
	Steam.network_messages_session_failed.connect(_on_session_failed)

func _process(_delta: float) -> void:
	if  NetworkManager.steam.lobby.id == 0:
		return
	#read_messages()

func send_message(
	message: Dictionary, 
	target: SteamUser = null, 
	type: send_type = send_type.RELIABLE
) -> void:
	var data: PackedByteArray = var_to_bytes(message).compress(FileAccess.COMPRESSION_GZIP)
	if target == null: # send to everyone
		for member in  NetworkManager.steam.lobby.members:
			if member.id ==  NetworkManager.steam.user.id:
				continue
			Steam.sendMessageToUser(member.id, data, type, CHANNEL)
	else:
		Steam.sendMessageToUser(target.id, data, type, CHANNEL)

func read_messages() -> void:
	var messages: Array = Steam.receiveMessagesOnChannel(CHANNEL, MAX_MESSAGES)
	for message in messages:
		if !message || message.is_empty():
			continue
		var decompressed_payload: PackedByteArray = message.payload.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		var payload: Dictionary = bytes_to_var(decompressed_payload \
			if decompressed_payload.size() > 0 \
			else message.payload
		)
		var _sender_id: int = message.identity

func close_session(user: SteamUser) -> void:
	if user.id ==  NetworkManager.local_user.steam.id:
		return
	var session: Dictionary = Steam.getSessionConnectionInfo(user.id, false, false)
	if !session || !session.connection_state || !session.connection_state == session_state.CONNECTED:
		return
	Steam.closeSessionWithUser(user.id)

func _on_session_request(user_id: int):
	Steam.acceptSessionWithUser(user_id)

func _on_session_failed(_user_id: int, _error: int, _state: int, debug_msg: String) -> void:
	printerr(debug_msg)
