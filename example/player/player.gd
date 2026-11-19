class_name Player
extends CharacterBody3D
## Example character, moved by the player who has authority over it and synchronized to
## the others by the MultiplayerSynchronizer of the scene.

const SPEED: float = 15.0
const JUMP_VELOCITY: float = 4.5
const ROTATION_SPEED: float = 20.0

@onready var _meshes: Node3D = $Meshes
@onready var _camera: Camera3D = $Camera
@onready var _name_label: Label3D = $NameLabel

func _ready() -> void:
	_camera.current = is_multiplayer_authority()
	var member: LobbyMember = Lobby.get_member(get_multiplayer_authority())
	_name_label.text = member.name if member != null else ""

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_move(delta)
	_face_movement(delta)

func _move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction: Vector3 = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()

func _face_movement(delta: float) -> void:
	if is_zero_approx(velocity.x) and is_zero_approx(velocity.z):
		return
	var angle: float = wrapf(atan2(velocity.x, velocity.z) - _meshes.rotation.y, -PI, PI)
	_meshes.rotation.y += clampf(ROTATION_SPEED * delta, 0, absf(angle)) * signf(angle)
