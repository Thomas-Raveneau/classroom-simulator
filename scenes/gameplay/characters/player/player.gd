extends CharacterBody3D
class_name Player

const SPEED: float = 15.0
const JUMP_VELOCITY: float = 4.5
const ROTATION_SPEED: float = 20

@onready var meshes: Node3D = $Meshes
@onready var camera: Camera3D = $Camera

func _ready() -> void:
	camera.current = is_multiplayer_authority()

func _input(event: InputEvent) -> void:
	if !is_multiplayer_authority():
		return
	if(!event.is_action_type()):
		return
	if event.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	movement(delta)
	rotate_player(delta)

func rotate_player(delta: float) -> void:
	if velocity == Vector3.ZERO: 
		return
	var theta: float = wrapf(atan2(velocity.x, velocity.z) - meshes.rotation.y, -PI, PI)
	meshes.rotation.y += clamp(ROTATION_SPEED * delta, 0, abs(theta)) * sign(theta)

func movement(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()
