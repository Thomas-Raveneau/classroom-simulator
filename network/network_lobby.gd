class_name NetworkLobby
extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

var players: Dictionary = {}

func _init(steam_user: SteamUser) -> void:
	var player = NetworkUser.new(steam_user)
	players[player.peer_id] = player

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_player_connected(peer_id: int) -> void:
	if peer_id == 1:
		return
	var steam_id: int = NetworkManager.peer.get_steam64_from_peer_id(peer_id)
	var steam_user: SteamUser = NetworkManager.steam.lobby.members[steam_id]
	var player = NetworkUser.new(steam_user)
	players[player.peer_id] = player
	print("PLAYER CONNECTED ", players)

func _on_player_disconnected(peer_id: int):
	print("PLAYER DISCONNECTED")
	players[peer_id].connected = false
	player_disconnected.emit(peer_id)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id].connected = true
	player_connected.emit(peer_id)
	print("CONNECTED OK ", players)

func _on_connected_fail():
	print("CONNECTED FAILED")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	print("SERVER DISCONNECTED")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
