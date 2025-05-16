class_name SpawnManager
extends MultiplayerSpawner

class SpawnInfo:
	var player_id: int
	var position: Vector3
	
	func _init(_player_id: int, _position: Vector3) -> void:
		player_id = _player_id
		position = _position

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
	spawn_function = _on_player_spawn
	if !is_multiplayer_authority():
		return
	NetworkManager.lobby.player_connected.connect(_on_player_connected)
	NetworkManager.lobby.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.players_ready.connect(spawn_players)

func has_spawnable_point() -> bool:
	return spawn_points.any(
		func (spawn_point: SpawnPoint) -> bool:
			return spawn_point.is_spawnable
	)

func get_spawnable_point() -> SpawnPoint:
	if !has_spawnable_point():
		return null
	spawn_points.shuffle()
	var index: int = spawn_points.find_custom(
		func (spawn_point: SpawnPoint) -> bool:
			return spawn_point.is_spawnable
	)
	return spawn_points[index]

func spawn_players() -> void:
	if !is_multiplayer_authority():
		return
	for player_id: int in NetworkManager.lobby.players.keys():
		spawn_player(player_id)

func spawn_player(player_id: int) -> void:
	if !is_multiplayer_authority():
		return
	if !NetworkManager.lobby.players.has(player_id):
		return
	if !has_spawnable_point():
		return delay_player_spawn(player_id)
	var spawn_point: SpawnPoint = get_spawnable_point()
	var spawn_info: SpawnInfo = SpawnInfo.new(player_id, spawn_point.position)
	spawn_point.use()
	spawn(spawn_info)

func delay_player_spawn(player_id: int, timer: Timer = null) -> void:
	if !is_multiplayer_authority():
		return
	if has_spawnable_point():
		if timer:
			timer.queue_free()
		return spawn_player(player_id)
	if timer:
		return
	var new_timer: Timer = Timer.new()
	new_timer.autostart = true
	new_timer.one_shot = false
	new_timer.wait_time = 0.1
	new_timer.timeout.connect(delay_player_spawn.bind(player_id, new_timer))
	add_child(new_timer)

func remove_player(player_id: int) -> void:
	if !player_instances.has(player_id):
		return
	var player_instance: Player = player_instances[player_id]
	player_instance.queue_free()
	player_instances.erase(player_id)

func _on_player_spawn(spawn_info: SpawnInfo) -> Player:
	print("SPAWN: ", spawn_info.player_id)
	var player_instance: Player = player_scene.instantiate()
	player_instance.set_multiplayer_authority(spawn_info.player_id)
	player_instance.position = spawn_info.position
	player_instances[spawn_info.player_id] = player_instance
	return player_instance

func _on_player_connected(player: NetworkPlayer) -> void:
	if !is_multiplayer_authority():
		return
	spawn_player(player.peer_id)

func _on_player_disconnected(player: NetworkPlayer) -> void:
	remove_player(player.peer_id)
