class_name MultiplayerNetwork
extends Node

const DEFAULT_PORT: int = 5000
const UPNP_MAX_RETRY: int = 100

var upnp: UPNP
var upnp_opened: bool = false
var thread: Thread
var ip: String
var port: int = DEFAULT_PORT

func create_server() -> bool:
	var upnp_result: UPNP.UPNPResult = open_upnp()
	if upnp_result != UPNP.UPNP_RESULT_SUCCESS:
		return false
	return open_server()

func open_upnp() -> UPNP.UPNPResult:
	upnp = UPNP.new()
	var result: UPNP.UPNPResult = upnp.discover()
	if result != UPNP.UPNP_RESULT_SUCCESS:
		return result
	var gateway: UPNPDevice = upnp.get_gateway()
	var test_ip = gateway.query_external_address()
	if !gateway:
		return UPNP.UPNP_RESULT_NO_GATEWAY
	#if gateway.is_valid_gateway():
		#return UPNP.UPNP_RESULT_INVALID_GATEWAY
	var success: bool = false
	for i in range(0, UPNP_MAX_RETRY):
		var udp_result: UPNP.UPNPResult = upnp.add_port_mapping(
			port, 
			port, 
			ProjectSettings.get_setting("application/config/name"), 
			"UDP"
		)
		var tcp_result: UPNP.UPNPResult = upnp.add_port_mapping(
			port, 
			port, 
			ProjectSettings.get_setting("application/config/name"), 
			"TCP"
		)
		if udp_result != UPNP.UPNP_RESULT_SUCCESS || tcp_result != UPNP.UPNP_RESULT_SUCCESS:
			port += 1
			continue
		success = true
		break
	if !success:
		return UPNP.UPNP_RESULT_NO_PORT_MAPS_AVAILABLE 
	upnp_opened = true
	ip = gateway.query_external_address()
	return UPNP.UPNP_RESULT_SUCCESS

func open_server() -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, GameSettings.MAX_PLAYERS)
	if error:
		return false
	multiplayer.multiplayer_peer = peer
	return true

func join_server(_ip: String, _port: int) -> bool:
	ip = _ip
	port = _port
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error:
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _exit_tree() -> void:
	if !upnp_opened:
		return
	upnp.delete_port_mapping(port, "UDP")
	upnp.delete_port_mapping(port, "TCP")
