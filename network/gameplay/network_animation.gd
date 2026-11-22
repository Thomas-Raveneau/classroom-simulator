class_name NetworkAnimation
extends Node
## Shows the animations of an object to the players who do not control it.
##
## Animate the object as in a single player game, but only on the player who has
## authority over it. Add this node as a child of the object: it publishes what plays
## there, and plays the same on the other players.
##
## - With an AnimationPlayer (`animation_player`): the animation being played is
##   mirrored, restarts included. Only its name travels: set the blend times on the
##   AnimationPlayer (`playback_default_blend_time`, `set_blend_time()`) rather than in
##   the call to `play()`. A player who joins later sees the animations that loop, and
##   the last pose of the others.
## - With an AnimationTree (`animation_tree`): list in `tree_parameters` the parameters
##   the game writes (blend positions, blend amounts...) and in `state_machines` the
##   state machines it drives. One-off requests (OneShot nodes) go through `fire()`.
##
## Make the MultiplayerSynchronizer of the object replicate `sync_state` of this node
## (replication mode "On Change") and, when `tree_parameters` is used, `sync_parameters`
## (replication mode "Always").

## Mirrored when there is no `animation_tree`.
@export var animation_player: AnimationPlayer
@export var animation_tree: AnimationTree
## Parameters of the tree copied from the owner to the others, e.g.
## `parameters/Move/blend_position`.
@export var tree_parameters: Array[StringName] = []
## Playback of the state machines of the tree whose current state is mirrored, e.g.
## `parameters/playback` or `parameters/Locomotion/playback`.
@export var state_machines: Array[StringName] = []
## Request parameters of the OneShot nodes of the tree that `fire()` may trigger, e.g.
## `parameters/Attack/request`.
@export var one_shots: Array[StringName] = []
## How fast numbers and vectors of `tree_parameters` catch up with the value received,
## so they do not change in steps. 0 applies them as they come.
@export_range(0.0, 60.0) var parameter_smoothing: float = 15.0

## Replicated: [animation, times an animation started, state of each state machine...,
## times each one-shot was fired...]. Replaced, never modified in place: the engine
## compares it with the previous one to know when to send it.
var sync_state: Array = []
## Replicated: the value of each of `tree_parameters`.
var sync_parameters: Array = []

## Owner: times an animation started on the AnimationPlayer, to tell a restart.
var _play_count: int = 0
## Owner: times each of `one_shots` was fired.
var _fire_counts: Array[int] = []
## Others: what was applied last.
var _seen_animation: StringName = &""
var _seen_play_count: int = 0
var _seen_fire_counts: Array[int] = []
var _has_state: bool = false
var _has_parameters: bool = false
## The state machine behind each of `state_machines`, null when it could not be found.
var _machines: Array[AnimationNodeStateMachine] = []

## Owner only. Triggers a OneShot node of the tree, here and on the other players.
## `request` must be one of `one_shots`.
func fire(request: StringName) -> void:
	var index: int = one_shots.find(request)
	if index == -1:
		push_error("NetworkAnimation: %s is not in the `one_shots` of %s." % [request, get_path()])
		return
	if not is_multiplayer_authority() or animation_tree == null:
		return
	animation_tree.set(request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_fire_counts[index] += 1

func _ready() -> void:
	_fire_counts.resize(one_shots.size())
	_fire_counts.fill(0)
	_seen_fire_counts.resize(one_shots.size())
	_seen_fire_counts.fill(0)
	for playback_path: StringName in state_machines:
		_machines.append(_find_state_machine(playback_path))
	if animation_player != null:
		animation_player.animation_started.connect(_on_animation_started)
	if is_multiplayer_authority():
		_publish()

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_publish()
	else:
		_apply(delta)

# --- Owner -------------------------------------------------------------------------------

func _publish() -> void:
	var animation: StringName = &""
	if animation_tree == null and animation_player != null:
		animation = _published_animation()
	var state: Array = [animation, _play_count]
	for playback_path: StringName in state_machines:
		var playback: AnimationNodeStateMachinePlayback = _playback(playback_path)
		state.append(playback.get_current_node() if playback != null else &"")
	state.append_array(_fire_counts)
	if state != sync_state:
		sync_state = state
	if animation_tree != null and not tree_parameters.is_empty():
		var values: Array = []
		for parameter: StringName in tree_parameters:
			values.append(animation_tree.get(parameter))
		sync_parameters = values

## What the others must play: the current animation, or the last one when it ended by
## itself, so a player who hears about it late still plays it. Empty once an animation
## that loops was stopped.
func _published_animation() -> StringName:
	var current: StringName = animation_player.current_animation
	if not current.is_empty():
		return current
	var last: StringName = animation_player.assigned_animation
	if animation_player.has_animation(last) and not _loops(last):
		return last
	return &""

func _on_animation_started(_animation: StringName) -> void:
	if is_multiplayer_authority():
		_play_count += 1

# --- Others ------------------------------------------------------------------------------

func _apply(delta: float) -> void:
	# Nothing received yet, or not what this object expects.
	if sync_state.size() == 2 + state_machines.size() + one_shots.size():
		if animation_tree == null:
			_apply_animation()
		else:
			_apply_states()
			_apply_fires()
		_has_state = true
	if animation_tree != null and sync_parameters.size() == tree_parameters.size():
		_apply_parameters(delta)
		_has_parameters = true

func _apply_animation() -> void:
	var animation: StringName = _read_name(sync_state[0])
	var play_count: int = _read_int(sync_state[1])
	if animation_player == null or (_has_state and animation == _seen_animation and play_count == _seen_play_count):
		return
	_seen_animation = animation
	_seen_play_count = play_count
	if animation.is_empty():
		# The owner stopped an animation that loops.
		if animation_player.is_playing():
			animation_player.pause()
	elif animation_player.has_animation(animation):
		if not _has_state and not _loops(animation):
			# Played before this player saw the object: only its last pose is shown.
			animation_player.play(animation)
			animation_player.seek(animation_player.get_animation(animation).length, true)
		elif animation_player.current_animation == animation:
			# Started again by the owner.
			animation_player.seek(0.0, true)
		else:
			animation_player.play(animation)

func _apply_states() -> void:
	for index: int in state_machines.size():
		var state: StringName = _read_name(sync_state[2 + index])
		var playback: AnimationNodeStateMachinePlayback = _playback(state_machines[index])
		var machine: AnimationNodeStateMachine = _machines[index]
		if playback == null or machine == null or state.is_empty() or not machine.has_node(state):
			continue
		# Checked at every frame, not only when it changes: a state machine also moves
		# by itself (automatic transitions), and must come back to where the owner is.
		if playback.get_current_node() == state:
			continue
		if not _has_state or not playback.is_playing():
			playback.start(state)
		else:
			var path: Array[StringName] = playback.get_travel_path()
			if path.is_empty() or path[-1] != state:
				playback.travel(state)

func _apply_fires() -> void:
	var offset: int = 2 + state_machines.size()
	for index: int in one_shots.size():
		var fire_count: int = _read_int(sync_state[offset + index])
		# What was fired before this player saw the object is not played late.
		if _has_state and fire_count != _seen_fire_counts[index]:
			animation_tree.set(one_shots[index], AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_seen_fire_counts[index] = fire_count

func _apply_parameters(delta: float) -> void:
	var weight: float = 1.0
	if _has_parameters and parameter_smoothing > 0.0:
		# Frame rate independent: the same share of the remaining gap per unit of time.
		weight = 1.0 - exp(-parameter_smoothing * delta)
	for index: int in tree_parameters.size():
		var parameter: StringName = tree_parameters[index]
		var current: Variant = animation_tree.get(parameter)
		var target: Variant = sync_parameters[index]
		# Only what the tree already holds, with the same type: this comes from a player.
		if current == null or typeof(current) != typeof(target):
			continue
		if target is float:
			var from: float = current
			var to: float = target
			if is_finite(to):
				animation_tree.set(parameter, lerpf(from, to, weight))
		elif target is Vector2:
			var from: Vector2 = current
			var to: Vector2 = target
			if to.is_finite():
				animation_tree.set(parameter, from.lerp(to, weight))
		else:
			animation_tree.set(parameter, target)

# --- Helpers -----------------------------------------------------------------------------

func _loops(animation: StringName) -> bool:
	return animation_player.get_animation(animation).loop_mode != Animation.LOOP_NONE

func _playback(playback_path: StringName) -> AnimationNodeStateMachinePlayback:
	if animation_tree == null:
		return null
	return animation_tree.get(playback_path) as AnimationNodeStateMachinePlayback

## Finds the state machine a playback path such as `parameters/Move/playback` refers to,
## to know which states exist.
func _find_state_machine(playback_path: StringName) -> AnimationNodeStateMachine:
	if animation_tree == null:
		return null
	var node: AnimationNode = animation_tree.tree_root
	var names: PackedStringArray = String(playback_path).split("/")
	# Between "parameters" and "playback": the nodes leading to the state machine.
	for index: int in range(1, names.size() - 1):
		if node is AnimationNodeBlendTree:
			node = (node as AnimationNodeBlendTree).get_node(names[index])
		elif node is AnimationNodeStateMachine:
			node = (node as AnimationNodeStateMachine).get_node(names[index])
		else:
			return null
	return node as AnimationNodeStateMachine

func _read_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""

func _read_int(value: Variant) -> int:
	return value if value is int else 0
