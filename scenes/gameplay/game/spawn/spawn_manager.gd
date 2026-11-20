class_name SpawnManager
extends MultiplayerSpawner
## The host spawns one player per lobby
## member, when that member has the game scene loaded.
##
## `Lobby.member_scene_ready` is emitted for every member when the game starts, then for
## each player joining in progress: nothing else is needed to support late arrivals.

@export var player_scene: PackedScene
@export var spawn_points: Array[SpawnPoint] = []

## Players waiting for a free spawn point.
var _waiting_peer_ids: Array[int] = []

func _ready() -> void:
	spawn_function = _create_player
	if not multiplayer.is_server():
		return
	Lobby.member_scene_ready.connect(_on_member_scene_ready)
	Lobby.member_left.connect(_on_member_left)
	for spawn_point: SpawnPoint in spawn_points:
		spawn_point.freed_up.connect(_spawn_waiting_players)

func _on_member_scene_ready(member: LobbyMember) -> void:
	_waiting_peer_ids.append(member.peer_id)
	_spawn_waiting_players()

func _on_member_left(member: LobbyMember) -> void:
	_waiting_peer_ids.erase(member.peer_id)
	var player: Node = get_node(spawn_path).get_node_or_null(str(member.peer_id))
	if player != null:
		# Freed on the host, despawned on everyone by the MultiplayerSpawner.
		player.queue_free()

func _spawn_waiting_players() -> void:
	while not _waiting_peer_ids.is_empty():
		var spawn_point: SpawnPoint = _pick_free_spawn_point()
		if spawn_point == null:
			return
		spawn_point.use()
		spawn({ "peer_id": _waiting_peer_ids.pop_front(), "position": spawn_point.global_position })

func _pick_free_spawn_point() -> SpawnPoint:
	var free_points: Array[SpawnPoint] = spawn_points.filter(
		func(spawn_point: SpawnPoint) -> bool: return spawn_point.is_free
	)
	return free_points.pick_random() if not free_points.is_empty() else null

## Runs on every player: builds the node the host asked to spawn.
func _create_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var player: Player = player_scene.instantiate() as Player
	player.name = str(peer_id)
	# The player controls its own character. The ReplicationGate of the scene keeps
	# itself under the authority of the host.
	player.set_multiplayer_authority(peer_id)
	player.position = data["position"]
	return player
