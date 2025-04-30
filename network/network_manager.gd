extends Node

var steam: SteamManager
var lobby: NetworkLobby
var peer: SteamMultiplayerPeer

func _ready() -> void:
	steam = SteamManager.new()
	lobby = NetworkLobby.new()
	peer = SteamMultiplayerPeer.new()
	add_child(steam)
	add_child(lobby)

func start_game() -> void:
	load_game.rpc(steam.lobby.members)
	#change_scene.rpc("res://scenes/maps/prototype/map_prototype.tscn")

@rpc("authority", "call_remote", "reliable")
func load_game(steam_lobby_members: Array[SteamUser]) -> void:
	lobby.set_players(steam_lobby_members)

func reset_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = null
	peer.close()
	peer = SteamMultiplayerPeer.new()

func set_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = peer

@rpc("authority", "call_local", "reliable")
func change_scene(scene_file: String) -> void:
	get_tree().change_scene_to_file(scene_file)
