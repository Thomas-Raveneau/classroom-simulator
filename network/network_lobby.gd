class_name NetworkLobby
extends Node

signal player_connected(player: NetworkPlayer)
signal player_disconnected(player: NetworkPlayer)
signal server_disconnected
signal on_loaded

var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func set_player(player: NetworkPlayer) -> void:
	if players.has(player.peer_id):
		return
	players[player.peer_id] = player

func has_steam_user(steam_id: int) -> bool:
	for player_id: int in players.keys():
		var player: NetworkPlayer = players[player_id]
		if player.steam.id == steam_id:
			return true
	return false

func check_if_loaded() -> void:
	if NetworkManager.steam.lobby.users_count == players.size():
		on_loaded.emit()

func _on_player_connected(peer_id: int) -> void:
	var steam_id: int = NetworkManager.peer.get_steam64_from_peer_id(peer_id)
	var steam_user: SteamUser = SteamUser.new(steam_id)
	var player: NetworkPlayer = NetworkPlayer.new(steam_user)
	player.is_host = steam_id == NetworkManager.steam.lobby.get_host_id()
	players[player.peer_id] = player
	player_connected.emit(player)
	check_if_loaded()

func _on_player_disconnected(peer_id: int) -> void:
	var disconnected_player: NetworkPlayer = players[peer_id]
	if disconnected_player.is_host:
		NetworkManager.steam.lobby.leave()
	players.erase(peer_id)
	player_disconnected.emit(disconnected_player)
	check_if_loaded()

func _on_connected_ok() -> void:
	var peer_id: int = NetworkManager.local_user.peer_id
	players[peer_id].connected = true
	player_connected.emit(players[peer_id])
	check_if_loaded()

func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	print("SERVER DISCONNECTED")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
