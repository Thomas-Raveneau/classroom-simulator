extends GutTest
## The animation mirror alone, without network: the authority of the object decides its
## role, and what would be received is written in `sync_state` / `sync_parameters`.

const MOVE_PLAYBACK: StringName = &"parameters/Move/playback"
const MIX_AMOUNT: StringName = &"parameters/Mix/blend_amount"
const WAVE_REQUEST: StringName = &"parameters/Wave/request"
const WAVE_ACTIVE: StringName = &"parameters/Wave/active"

var _object: Node3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _animation: NetworkAnimation

func before_each() -> void:
	_object = Node3D.new()
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(&"idle", _make_animation(Animation.LOOP_LINEAR))
	library.add_animation(&"run", _make_animation(Animation.LOOP_LINEAR))
	library.add_animation(&"wave", _make_animation(Animation.LOOP_NONE))
	_player.add_animation_library(&"", library)
	_object.add_child(_player)
	_animation = NetworkAnimation.new()
	_animation.animation_player = _player
	_object.add_child(_animation)
	_tree = null

func _make_animation(loop_mode: Animation.LoopMode) -> Animation:
	var animation: Animation = Animation.new()
	animation.length = 0.2
	animation.loop_mode = loop_mode
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, ^".:position")
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 0.2, Vector3.UP)
	return animation

## Drives the object with an AnimationTree instead: a state machine "Move" (idle, run),
## mixed with the run animation by "Mix", under a one-shot "Wave".
func _use_a_tree() -> void:
	var machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	machine.add_node(&"idle", _animation_node(&"idle"))
	machine.add_node(&"run", _animation_node(&"run"))
	var start: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(&"Start", &"idle", start)
	machine.add_transition(&"idle", &"run", AnimationNodeStateMachineTransition.new())
	machine.add_transition(&"run", &"idle", AnimationNodeStateMachineTransition.new())
	var root: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	root.add_node(&"Move", machine)
	root.add_node(&"Run", _animation_node(&"run"))
	root.add_node(&"Mix", AnimationNodeBlend2.new())
	root.add_node(&"WaveAnimation", _animation_node(&"wave"))
	root.add_node(&"Wave", AnimationNodeOneShot.new())
	root.connect_node(&"Mix", 0, &"Move")
	root.connect_node(&"Mix", 1, &"Run")
	root.connect_node(&"Wave", 0, &"Mix")
	root.connect_node(&"Wave", 1, &"WaveAnimation")
	root.connect_node(&"output", 0, &"Wave")
	_tree = AnimationTree.new()
	_tree.tree_root = root
	_tree.anim_player = ^"../AnimationPlayer"
	_object.add_child(_tree)
	_animation.animation_tree = _tree
	_animation.tree_parameters = [MIX_AMOUNT]
	_animation.state_machines = [MOVE_PLAYBACK]
	_animation.one_shots = [WAVE_REQUEST]

func _animation_node(animation: StringName) -> AnimationNodeAnimation:
	var node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	node.animation = animation
	return node

## Puts the object in the tree as owned by the local player or by another one.
func _add_object(is_local: bool) -> void:
	_object.set_multiplayer_authority(multiplayer.get_unique_id() if is_local else 999)
	add_child_autofree(_object)

func _playback() -> AnimationNodeStateMachinePlayback:
	return _tree.get(MOVE_PLAYBACK) as AnimationNodeStateMachinePlayback

# --- AnimationPlayer ---------------------------------------------------------------------

func test_owner_publishes_the_animation_it_plays() -> void:
	_add_object(true)
	_player.play(&"run")
	await wait_process_frames(2)
	assert_eq(_animation.sync_state[0], &"run")
	_player.play(&"idle")
	await wait_process_frames(2)
	assert_eq(_animation.sync_state[0], &"idle")

func test_owner_tells_when_the_same_animation_starts_again() -> void:
	_add_object(true)
	_player.play(&"wave")
	await wait_process_frames(2)
	var first_state: Array = _animation.sync_state
	await wait_until(func() -> bool: return not _player.is_playing(), 2.0)
	_player.play(&"wave")
	await wait_process_frames(2)
	assert_eq(_animation.sync_state[0], &"wave")
	assert_ne(_animation.sync_state, first_state, "a restart is a change to send")

func test_owner_keeps_publishing_an_animation_that_ended() -> void:
	_add_object(true)
	_player.play(&"wave")
	await wait_until(func() -> bool: return not _player.is_playing(), 2.0)
	await wait_process_frames(2)
	assert_eq(_animation.sync_state[0], &"wave", "a player hearing about it late still plays it")
	_player.play(&"run")
	await wait_process_frames(2)
	_player.stop()
	await wait_process_frames(2)
	assert_eq(_animation.sync_state[0], &"", "a stopped loop is not playing anymore")

func test_owner_is_not_driven_by_received_values() -> void:
	_add_object(true)
	_player.play(&"idle")
	await wait_process_frames(2)
	_animation.sync_state = [&"run", 99]
	await wait_process_frames(2)
	assert_eq(_player.current_animation, &"idle")

func test_remote_plays_the_animation_received() -> void:
	_add_object(false)
	await wait_process_frames(2)
	assert_false(_player.is_playing(), "nothing plays before anything is received")
	_animation.sync_state = [&"run", 1]
	await wait_process_frames(2)
	assert_eq(_player.current_animation, &"run")
	_animation.sync_state = [&"idle", 2]
	await wait_process_frames(2)
	assert_eq(_player.current_animation, &"idle")

func test_remote_shows_the_last_pose_of_what_was_played_before_it_came() -> void:
	_add_object(false)
	_animation.sync_state = [&"wave", 5]
	await wait_process_frames(3)
	assert_false(_player.is_playing(), "not played late")
	assert_eq(_object.position, Vector3.UP, "but left as the animation leaves it")

func test_remote_plays_again_an_animation_started_again() -> void:
	_add_object(false)
	_animation.sync_state = [&"idle", 0]
	await wait_process_frames(2)
	_animation.sync_state = [&"wave", 1]
	await wait_process_frames(2)
	assert_true(_player.is_playing(), "plays what the owner started")
	await wait_until(func() -> bool: return not _player.is_playing(), 2.0)
	assert_false(_player.is_playing(), "played once")
	_animation.sync_state = [&"wave", 2]
	await wait_process_frames(2)
	assert_true(_player.is_playing(), "plays again")
	assert_eq(_player.current_animation, &"wave")

func test_remote_stops_a_looping_animation_the_owner_stopped() -> void:
	_add_object(false)
	_animation.sync_state = [&"run", 1]
	await wait_process_frames(2)
	assert_true(_player.is_playing())
	_animation.sync_state = [&"", 1]
	await wait_process_frames(2)
	assert_false(_player.is_playing())

func test_remote_ignores_what_it_cannot_play() -> void:
	_add_object(false)
	_animation.sync_state = [&"unknown", 1]
	await wait_process_frames(2)
	assert_false(_player.is_playing(), "unknown animation")
	_animation.sync_state = [12, "text"]
	await wait_process_frames(2)
	assert_false(_player.is_playing(), "wrong types")
	_animation.sync_state = [&"run", 1, &"extra"]
	await wait_process_frames(2)
	assert_false(_player.is_playing(), "wrong size")
	assert_engine_error_count(0)

# --- AnimationTree -----------------------------------------------------------------------

func test_owner_publishes_the_tree() -> void:
	_use_a_tree()
	_add_object(true)
	_tree.set(MIX_AMOUNT, 0.7)
	await wait_until(func() -> bool: return _playback().get_current_node() == &"idle", 2.0)
	_playback().travel(&"run")
	await wait_until(func() -> bool: return _playback().get_current_node() == &"run", 2.0)
	await wait_process_frames(2)
	assert_eq(_animation.sync_parameters.size(), 1)
	assert_almost_eq(_animation.sync_parameters[0] as float, 0.7, 0.001)
	assert_eq(_animation.sync_state[2], &"run", "state of the state machine")

func test_remote_tree_parameters_follow_smoothly() -> void:
	_use_a_tree()
	_add_object(false)
	_animation.sync_parameters = [1.0]
	await wait_process_frames(2)
	assert_almost_eq(_tree.get(MIX_AMOUNT) as float, 1.0, 0.001, "the first value is applied at once")
	_animation.sync_parameters = [0.0]
	await wait_process_frames(1)
	assert_between(_tree.get(MIX_AMOUNT) as float, 0.01, 0.99, "neither still nor already there")
	await wait_until(func() -> bool: return (_tree.get(MIX_AMOUNT) as float) < 0.01, 2.0)
	assert_almost_eq(_tree.get(MIX_AMOUNT) as float, 0.0, 0.01, "it ends where the owner said")

func test_remote_tree_ignores_values_of_another_type() -> void:
	_use_a_tree()
	_add_object(false)
	_animation.sync_parameters = [0.4]
	await wait_process_frames(2)
	_animation.sync_parameters = ["text"]
	await wait_process_frames(2)
	_animation.sync_parameters = [NAN]
	await wait_process_frames(2)
	assert_almost_eq(_tree.get(MIX_AMOUNT) as float, 0.4, 0.001)
	assert_engine_error_count(0)

func test_remote_state_machine_goes_where_the_owner_is() -> void:
	_use_a_tree()
	_add_object(false)
	_animation.sync_state = [&"", 0, &"run", 0]
	await wait_until(func() -> bool: return _playback().get_current_node() == &"run", 2.0)
	assert_eq(_playback().get_current_node(), &"run")
	_animation.sync_state = [&"", 0, &"idle", 0]
	await wait_until(func() -> bool: return _playback().get_current_node() == &"idle", 2.0)
	assert_eq(_playback().get_current_node(), &"idle")
	_animation.sync_state = [&"", 0, &"unknown", 0]
	await wait_process_frames(3)
	assert_eq(_playback().get_current_node(), &"idle", "an unknown state is ignored")
	assert_engine_error_count(0)

func test_remote_one_shot_plays_when_the_owner_fires() -> void:
	_use_a_tree()
	_add_object(false)
	_animation.sync_state = [&"", 0, &"idle", 3]
	await wait_process_frames(3)
	assert_false(_tree.get(WAVE_ACTIVE) as bool, "what was fired before is not played late")
	_animation.sync_state = [&"", 0, &"idle", 4]
	await wait_until(func() -> bool: return _tree.get(WAVE_ACTIVE) as bool, 2.0)
	assert_true(_tree.get(WAVE_ACTIVE) as bool)

func test_owner_fires_a_one_shot() -> void:
	_use_a_tree()
	_add_object(true)
	await wait_process_frames(2)
	var fired_before: int = _animation.sync_state[3]
	_animation.fire(WAVE_REQUEST)
	await wait_until(func() -> bool: return _tree.get(WAVE_ACTIVE) as bool, 2.0)
	assert_true(_tree.get(WAVE_ACTIVE) as bool, "plays on the owner")
	assert_eq(_animation.sync_state[3], fired_before + 1, "and is published")
	_animation.fire(&"parameters/Other/request")
	assert_push_error("is not in the `one_shots`")
