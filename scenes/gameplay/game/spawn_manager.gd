class_name SpawnManager
extends MultiplayerSpawner

@export var player_scene: PackedScene
@export var players_container: Node3D

var player_instances : Dictionary = {}

func _ready() -> void:
	if !players_container:
		push_error("players_container not set")
		return
	if !player_scene:
		push_error("player_scene not set")
		return
	spawn_function = spawn_player
	if !is_multiplayer_authority():
		return
	NetworkManager.lobby.player_connected.connect(_on_player_connected)
	NetworkManager.lobby.player_disconnected.connect(_on_player_disconnected)
	for player_id in NetworkManager.lobby.players.keys():
		spawn(player_id) 

func spawn_player(player_peer_id: int) -> Player:
	var player_instance: Player = player_scene.instantiate()
	player_instance.set_multiplayer_authority(player_peer_id)
	player_instances[player_peer_id] = player_instance
	return player_instance

func remove_player(player_peer_id: int) -> void:
	if !player_instances.has(player_peer_id):
		return
	player_instances[player_peer_id].queue_free()
	player_instances.erase(player_peer_id)

func _on_player_connected(player: NetworkPlayer) -> void:
	spawn(player.peer_id)

func _on_player_disconnected(player: NetworkPlayer) -> void:
	remove_player(player.peer_id)
