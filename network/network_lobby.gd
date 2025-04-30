class_name NetworkLobby
extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

var players: Array[NetworkPlayer] = []

func _init(steam_lobby_members: Array[SteamUser]) -> void:
	for steam_lobby_member in steam_lobby_members:
		var player = NetworkPlayer.new(steam_lobby_member)
		players.append(player)

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null
	players.clear()

@rpc("call_local", "reliable")
func load_game(game_scene_path):
	get_tree().change_scene_to_file(game_scene_path)

@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	pass
	#if multiplayer.is_server():
		#players_loaded += 1
		#if players_loaded == players.size():
			#$/root/Game.start_game()
			#players_loaded = 0

func update_player(peer_id: int, data: Dictionary) -> void:
	for player in players:
		if player.peer_id != peer_id:
			continue
		for key in data.keys():
			player[key] = data[key]

func _on_player_connected(peer_id: int):
	print("PLAYER CONNECTED")
	update_player(peer_id, { connected = true })

#@rpc("any_peer", "reliable")
#func _register_player(new_player_info):
	#print("REGISTER PLAYER")
	#var new_player_id = multiplayer.get_remote_sender_id()
	#players[new_player_id] = new_player_info
	#player_connected.emit(new_player_id, new_player_info)

func _on_player_disconnected(peer_id: int):
	print("PLAYER DISCONNECTED")
	update_player(peer_id, { connected = false })
	player_disconnected.emit(peer_id)

func _on_connected_ok():
	print("CONNECTED OK")
	var peer_id = multiplayer.get_unique_id()
	update_player(peer_id, { connected = true })
	player_connected.emit(peer_id)

func _on_connected_fail():
	print("CONNECTED FAILED")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	print("SERVER DISCONNECTED")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
