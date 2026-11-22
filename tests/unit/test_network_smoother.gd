extends GutTest
## The smoother alone, without network: the authority of the object decides its role.

var _object: Node3D
var _smoother: NetworkSmoother

func before_each() -> void:
	_object = Node3D.new()
	_smoother = NetworkSmoother.new()
	_object.add_child(_smoother)

## Puts the object in the tree as owned by the local player or by another one.
func _add_object(is_local: bool) -> void:
	_object.set_multiplayer_authority(multiplayer.get_unique_id() if is_local else 999)
	add_child_autofree(_object)

func test_owner_publishes_where_the_object_is() -> void:
	_object.position = Vector3(1, 2, 3)
	_add_object(true)
	assert_eq(_smoother.sync_position, Vector3(1, 2, 3), "published as soon as it is ready")
	_object.position = Vector3(4, 5, 6)
	_object.rotation = Vector3(0, 1, 0)
	await wait_physics_frames(2)
	assert_eq(_smoother.sync_position, Vector3(4, 5, 6))
	assert_almost_eq(_smoother.sync_rotation.y, 1.0, 0.001)

func test_owner_is_not_moved_by_received_values() -> void:
	_add_object(true)
	_object.position = Vector3(1, 0, 0)
	await wait_process_frames(3)
	assert_eq(_object.position, Vector3(1, 0, 0))

func test_remote_object_slides_toward_the_received_position() -> void:
	_add_object(false)
	_smoother.sync_position = Vector3(2, 0, 0)
	await wait_process_frames(1)
	assert_between(_object.position.x, 0.01, 1.99, "neither still nor already there")
	await wait_until(func() -> bool: return _object.position.distance_to(Vector3(2, 0, 0)) < 0.01, 2.0)
	assert_almost_eq(_object.position.x, 2.0, 0.01, "it ends where the owner said")
	assert_ne(_smoother.sync_position, _object.position * 0.0, "received values are not overwritten")

func test_remote_object_jumps_beyond_the_teleport_distance() -> void:
	_add_object(false)
	_smoother.sync_position = Vector3(_smoother.teleport_distance + 1.0, 0, 0)
	await wait_process_frames(1)
	assert_eq(_object.position, _smoother.sync_position)

func test_remote_rotation_follows_on_its_own_node() -> void:
	var visual: Node3D = Node3D.new()
	_object.add_child(visual)
	_smoother.rotation_node = visual
	_add_object(false)
	_smoother.sync_rotation = Vector3(0, PI / 2, 0)
	await wait_until(func() -> bool: return absf(visual.rotation.y - PI / 2) < 0.01, 2.0)
	assert_almost_eq(visual.rotation.y, PI / 2, 0.01)
	assert_eq(_object.rotation, Vector3.ZERO, "the body does not rotate")

func test_remote_object_jumps_after_a_teleport_of_the_owner_even_nearby() -> void:
	_add_object(false)
	_smoother.sync_position = Vector3(1, 0, 0)
	_smoother.sync_teleport_count += 1
	await wait_process_frames(1)
	assert_eq(_object.position, Vector3(1, 0, 0))

func test_owner_teleport_is_published() -> void:
	_add_object(true)
	_object.position = Vector3(3, 0, 0)
	_smoother.teleport()
	assert_eq(_smoother.sync_position, Vector3(3, 0, 0))
	assert_eq(_smoother.sync_teleport_count, 1)
