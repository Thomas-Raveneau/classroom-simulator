class_name NetworkSmoother
extends Node
## Makes an object controlled by another player move smoothly between two network updates.
##
## Add it as a child of the object, and make the MultiplayerSynchronizer of the object
## replicate `sync_position` and `sync_rotation` of this node instead of the position and
## rotation of the object itself. Updates can then be sent less often (see
## `MultiplayerSynchronizer.replication_interval`) without the object moving in steps.
##
## - On the player who has authority over the object: publishes where it is.
## - On the other players: moves the object toward the last value received, and jumps
##   straight to it beyond `teleport_distance` (respawn, teleporter).

## Node whose position is synchronized. The parent by default.
@export var position_node: Node3D
## Node whose rotation is synchronized. The parent by default. Can be another node
## than `position_node`, e.g. the visual part of a character.
@export var rotation_node: Node3D
## How fast the object catches up with the value received. Higher is snappier.
@export_range(1.0, 60.0) var smoothing_speed: float = 18.0
## Beyond this distance the object is placed directly instead of sliding there.
@export var teleport_distance: float = 5.0

## Replicated: where the authority says the object is.
var sync_position: Vector3
var sync_rotation: Vector3

func _ready() -> void:
	if position_node == null:
		position_node = get_parent() as Node3D
	if rotation_node == null:
		rotation_node = get_parent() as Node3D
	_publish()

func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority():
		_publish()

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		return
	# Frame rate independent: the same share of the remaining distance per unit of time.
	var weight: float = 1.0 - exp(-smoothing_speed * delta)
	if position_node != null:
		if position_node.position.distance_to(sync_position) > teleport_distance:
			position_node.position = sync_position
		else:
			position_node.position = position_node.position.lerp(sync_position, weight)
	if rotation_node != null:
		rotation_node.quaternion = rotation_node.quaternion.slerp(Quaternion.from_euler(sync_rotation), weight)

func _publish() -> void:
	if position_node != null:
		sync_position = position_node.position
	if rotation_node != null:
		sync_rotation = rotation_node.rotation
