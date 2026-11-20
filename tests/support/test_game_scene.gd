class_name LobbyTestGameScene
extends Node
## Minimal game scene of the replication tests: a NetworkSpawner whose host spawns one
## "pawn" per member having the scene loaded, as a real game would, and a "beacon" that
## belongs to the scene.

var spawner: NetworkSpawner
var pawns: Node
var beacon: LobbyTestBeacon
var match_state: MatchState
var pawn_scene: PackedScene
var _lobby: LobbyService

func _init() -> void:
	pawns = Node.new()
	pawns.name = "Pawns"
	add_child(pawns)
	beacon = LobbyTestBeacon.new()
	beacon.name = "Beacon"
	add_child(beacon)
	match_state = MatchState.new()
	match_state.name = "MatchState"
	add_child(match_state)
	pawn_scene = PackedScene.new()
	var pawn: LobbyTestPawn = LobbyTestPawn.new()
	pawn_scene.pack(pawn)
	pawn.free()
	spawner = NetworkSpawner.new()
	spawner.name = "Spawner"
	spawner.scenes = [pawn_scene]
	add_child(spawner)

func _ready() -> void:
	spawner.spawn_path = spawner.get_path_to(pawns)
	_lobby = LobbyService.for_node(self)
	if multiplayer.is_server():
		_lobby.member_scene_ready.connect(_on_member_scene_ready)
		_lobby.member_left.connect(_on_member_left)

func get_pawn(peer_id: int) -> LobbyTestPawn:
	return pawns.get_node_or_null(str(peer_id)) as LobbyTestPawn

func _on_member_scene_ready(member: LobbyMember) -> void:
	spawner.spawn_scene(pawn_scene, {}, member.peer_id, str(member.peer_id))

func _on_member_left(member: LobbyMember) -> void:
	var pawn: LobbyTestPawn = get_pawn(member.peer_id)
	if pawn != null:
		pawn.queue_free()
