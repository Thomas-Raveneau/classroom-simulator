extends Node

var lobby: MultiplayerLobby
var network: MultiplayerNetwork

func _ready() -> void:
	lobby = MultiplayerLobby.new()
	network = MultiplayerNetwork.new()
	add_child(lobby)
	add_child(network)

func host_game() -> bool:
	var success: bool = network.create_server()
	return success

func join_game(ip: String, port: int) -> bool:
	var success: bool = network.join_server(ip, port)
	return success
