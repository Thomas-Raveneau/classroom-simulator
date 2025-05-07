extends Node

var steam: SteamManager
var lobby: NetworkLobby
var local_user: NetworkUser
var peer: SteamMultiplayerPeer

func _ready() -> void:
	steam = SteamManager.new()
	lobby = NetworkLobby.new()
	local_user = NetworkUser.new()
	local_user.set_steam(steam.get_local_user())
	peer = SteamMultiplayerPeer.new()
	add_child(steam)
	add_child(lobby)
	steam.lobby.on_created.connect(_on_lobby_joined)
	steam.lobby.on_joined.connect(_on_lobby_joined)
	steam.lobby.on_left.connect(_on_lobby_left)

func start_game() -> void:
	change_scene.rpc("res://scenes/maps/prototype/map_prototype.tscn")

func reset_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = null
	peer.close()
	peer = SteamMultiplayerPeer.new()

@rpc("authority", "call_local", "reliable")
func change_scene(scene_file: String) -> void:
	get_tree().change_scene_to_file(scene_file)

func _on_lobby_joined() -> void:
	multiplayer.multiplayer_peer = peer
	local_user.peer_id = peer.get_unique_id()
	lobby.set_player(local_user)

func _on_lobby_left() -> void:
	lobby = NetworkLobby.new()
	reset_multiplayer_peer()
