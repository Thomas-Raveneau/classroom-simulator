extends Node

var steam: SteamManager
var lobby: NetworkLobby
var peer: SteamMultiplayerPeer

func _ready() -> void:
	steam = SteamManager.new()
	peer = SteamMultiplayerPeer.new()
	add_child(steam)

func start_game() -> void:
	print(steam.lobby.members)
	lobby = NetworkLobby.new(steam.lobby.members)
	add_child(lobby)
	change_scene("res://scenes/maps/prototype/map_prototype.tscn")

func reset_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = null
	peer.close()
	peer = SteamMultiplayerPeer.new()

func set_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = peer

@rpc("authority", "call_local", "reliable")
func change_scene(scene_file: String) -> void:
	get_tree().change_scene_to_file(scene_file)
