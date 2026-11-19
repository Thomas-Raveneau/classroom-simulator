class_name TestGameScene
extends Node
## Minimal game scene of the replication tests: a MultiplayerSpawner whose host spawns
## one "pawn" per member having the scene loaded, as a real game would.

const PAWN_SCRIPT: GDScript = preload("res://tests/support/test_pawn.gd")

var spawner: MultiplayerSpawner
var pawns: Node
var _lobby: LobbyService

func _init() -> void:
	pawns = Node.new()
	pawns.name = "Pawns"
	add_child(pawns)
	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_function = _spawn_pawn
	add_child(spawner)

func _ready() -> void:
	spawner.spawn_path = spawner.get_path_to(pawns)
	_lobby = LobbyService.for_node(self)
	if multiplayer.is_server():
		_lobby.member_scene_ready.connect(_on_member_scene_ready)
		_lobby.member_left.connect(_on_member_left)

func get_pawn(peer_id: int) -> TestPawn:
	return pawns.get_node_or_null(str(peer_id)) as TestPawn

func _on_member_scene_ready(member: LobbyMember) -> void:
	spawner.spawn(member.peer_id)

func _on_member_left(member: LobbyMember) -> void:
	var pawn: TestPawn = get_pawn(member.peer_id)
	if pawn != null:
		pawn.queue_free()

func _spawn_pawn(peer_id: int) -> Node:
	var pawn: TestPawn = PAWN_SCRIPT.new()
	pawn.name = str(peer_id)
	pawn.set_multiplayer_authority(peer_id)
	return pawn
