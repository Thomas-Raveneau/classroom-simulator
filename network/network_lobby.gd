class_name NetworkLobby
extends Node

signal player_connected(player: NetworkUser)
signal player_disconnected(player: NetworkUser)
signal server_disconnected

var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func set_player(player: NetworkUser) -> void:
	if players.has(player.peer_id):
		return
	players[player.peer_id] = player

func has_steam_user(steam_id: int) -> bool:
	for player_id in players.keys():
		var player: NetworkUser = players[player_id]
		if player.steam.id == steam_id:
			return true
	return false

func _on_player_connected(peer_id: int) -> void:
	var steam_id: int = NetworkManager.peer.get_steam64_from_peer_id(peer_id)
	var steam_user := SteamUser.new(steam_id)
	var player := NetworkUser.new(steam_user)
	player.is_host = steam_id == NetworkManager.steam.lobby.get_host_id()
	players[player.peer_id] = player
	player_connected.emit(player)

func _on_player_disconnected(peer_id: int):
	print("PLAYER DISCONNECTED")
	var disconnected_player: NetworkUser = players[peer_id]
	players.erase(peer_id)
	player_disconnected.emit(disconnected_player)

func _on_connected_ok():
	var peer_id = NetworkManager.local_user.peer_id
	print("CONNECTED OK ", peer_id, players)
	players[peer_id].connected = true
	player_connected.emit(players[peer_id])

func _on_connected_fail():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	print("SERVER DISCONNECTED")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
