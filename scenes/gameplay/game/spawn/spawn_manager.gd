class_name SpawnManager
extends MultiplayerSpawner

@export var player_scene: PackedScene
@export var spawn_points: Array[SpawnPoint]

var player_instances : Dictionary = {}

func _ready() -> void:
	if !player_scene:
		push_error("player_scene not set")
		return
	if spawn_points.size() == 0:
		push_error("set at least one spawn point")
		return
	spawn_function = spawn_player
	if !is_multiplayer_authority():
		return
	NetworkManager.lobby.player_connected.connect(_on_player_connected)
	NetworkManager.lobby.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.players_ready.connect(spawn_players)

func spawn_players() -> void:
	for player_id: int in NetworkManager.lobby.players.keys():
		spawn(player_id)

func get_available_spawn_point() -> SpawnPoint:
	var spawn_point: SpawnPoint = null
	while !spawn_point:
		var random_spawn_point: SpawnPoint = spawn_points.pick_random()
		if !random_spawn_point.is_spawnable:
			continue
		spawn_point = random_spawn_point
	return spawn_point

func spawn_player(player_peer_id: int) -> Player:
	var spawn_point: SpawnPoint = get_available_spawn_point()
	var player_instance: Player = player_scene.instantiate()
	player_instance.set_multiplayer_authority(player_peer_id)
	player_instance.position = spawn_point.position
	spawn_point.use()
	player_instances[player_peer_id] = player_instance
	return player_instance

func remove_player(player_peer_id: int) -> void:
	if !player_instances.has(player_peer_id):
		return
	var player_instance: Player = player_instances[player_peer_id]
	player_instance.queue_free()
	player_instances.erase(player_peer_id)

func _on_player_connected(player: NetworkPlayer) -> void:
	spawn(player.peer_id)

func _on_player_disconnected(player: NetworkPlayer) -> void:
	remove_player(player.peer_id)
