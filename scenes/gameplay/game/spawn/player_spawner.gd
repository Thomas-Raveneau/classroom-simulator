class_name PlayerSpawner
extends NetworkSpawner
## The host spawns one character per lobby member, when that member has the game scene
## loaded.
##
## `Lobby.member_scene_ready` is emitted for every member when the game starts, then for
## each player joining in progress: nothing else is needed to support late arrivals.

@export var player_scene: PackedScene
@export var spawn_points: Array[SpawnPoint] = []

## Players waiting for a free spawn point.
var _waiting_peer_ids: Array[int] = []

func _ready() -> void:
	if not scenes.has(player_scene):
		scenes.append(player_scene)
	if not multiplayer.is_server():
		return
	Lobby.member_scene_ready.connect(_on_member_scene_ready)
	Lobby.member_left.connect(_on_member_left)
	for spawn_point: SpawnPoint in spawn_points:
		spawn_point.freed_up.connect(_spawn_waiting_players)

## The character of a member, null when it has none (yet).
func get_player(peer_id: int) -> Player:
	return get_node(spawn_path).get_node_or_null(str(peer_id)) as Player

func _on_member_scene_ready(member: LobbyMember) -> void:
	_waiting_peer_ids.append(member.peer_id)
	_spawn_waiting_players()

func _on_member_left(member: LobbyMember) -> void:
	_waiting_peer_ids.erase(member.peer_id)
	var player: Player = get_player(member.peer_id)
	if player != null:
		# Freed on the host, despawned on everyone by the spawner.
		player.queue_free()

func _spawn_waiting_players() -> void:
	while not _waiting_peer_ids.is_empty():
		var spawn_point: SpawnPoint = _pick_free_spawn_point()
		if spawn_point == null:
			return
		spawn_point.use()
		var peer_id: int = _waiting_peer_ids.pop_front()
		# The player controls its own character, named after its peer id.
		spawn_scene(player_scene, { "position": spawn_point.global_position }, peer_id, str(peer_id))

func _pick_free_spawn_point() -> SpawnPoint:
	var free_points: Array[SpawnPoint] = spawn_points.filter(
		func(spawn_point: SpawnPoint) -> bool: return spawn_point.is_free
	)
	return free_points.pick_random() if not free_points.is_empty() else null
