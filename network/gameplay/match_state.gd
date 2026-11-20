class_name MatchState
extends Node
## The state of the match, shared by every player: current phase and its timer, scores,
## and any other value the game needs everyone to agree on.
##
## Add one to the game scene. Only the host writes; every change reaches the players
## whose game scene is loaded, and a player joining in progress receives the whole state.
## Scores are kept by user id, not by connection: they survive a reconnection.
##
## This node receives RPCs: it must have the same name and path on every player.

signal phase_changed(phase: StringName)
## The timer of the current phase reached zero. The host decides what comes next.
signal phase_time_elapsed(phase: StringName)
signal score_changed(user_id: int, score: int)
signal value_changed(key: String)

## Phases used by default. A game can use any other name.
const PHASE_WAITING: StringName = &"waiting"
const PHASE_COUNTDOWN: StringName = &"countdown"
const PHASE_PLAYING: StringName = &"playing"
const PHASE_RESULTS: StringName = &"results"

var phase: StringName = PHASE_WAITING
## Seconds left in the current phase, counted down locally. 0 when the phase has no timer.
var time_left: float = 0.0
## Score of each player, by user id (`LobbyMember.user_id`).
var scores: Dictionary[int, int] = {}

var _values: Dictionary[String, Variant] = {}
var _has_timer: bool = false
var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)
	if _lobby != null and multiplayer.is_server():
		_lobby.member_scene_ready.connect(_on_member_scene_ready)

func _process(delta: float) -> void:
	if not _has_timer:
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left == 0.0:
		_has_timer = false
		phase_time_elapsed.emit(phase)

# --- Host API ----------------------------------------------------------------------------

## Host only. Enters a phase, with a timer when `duration` is positive.
func start_phase(new_phase: StringName, duration: float = 0.0) -> void:
	if multiplayer.is_server():
		_send(_set_phase, [new_phase, duration])

## Host only.
func set_score(user_id: int, score: int) -> void:
	if multiplayer.is_server() and get_score(user_id) != score:
		_send(_set_score, [user_id, score])

## Host only.
func add_score(user_id: int, points: int = 1) -> void:
	set_score(user_id, get_score(user_id) + points)

## Host only.
func reset_scores() -> void:
	for user_id: int in scores.keys():
		set_score(user_id, 0)

## Host only. Shares any other value. Only use types that can be sent over the network,
## no objects. A null value erases the key.
func set_value(key: String, value: Variant) -> void:
	if multiplayer.is_server():
		_send(_set_value, [key, value])

# --- Reading -----------------------------------------------------------------------------

func get_score(user_id: int) -> int:
	return scores.get(user_id, 0)

func get_value(key: String, default: Variant = null) -> Variant:
	return _values.get(key, default)

## User ids from the best score to the lowest.
func get_ranking() -> Array[int]:
	var ranking: Array[int] = scores.keys()
	ranking.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
	return ranking

# --- Synchronization ---------------------------------------------------------------------

## Applies a change on the host, then on every player whose game scene is loaded.
func _send(method: Callable, arguments: Array) -> void:
	method.callv(arguments)
	if _lobby == null:
		return
	for peer_id: int in _lobby.scene_ready_peers:
		if peer_id != multiplayer.get_unique_id():
			method.rpc_id.callv([peer_id] + arguments)

func _on_member_scene_ready(member: LobbyMember) -> void:
	if member.peer_id != multiplayer.get_unique_id():
		_snapshot.rpc_id(member.peer_id, phase, time_left if _has_timer else 0.0, scores, _values)

@rpc("authority", "call_remote", "reliable")
func _snapshot(
	current_phase: StringName, current_time_left: float, current_scores: Dictionary,
	current_values: Dictionary
) -> void:
	scores.clear()
	for user_id: Variant in current_scores:
		if user_id is int and current_scores[user_id] is int:
			scores[user_id] = current_scores[user_id]
			score_changed.emit(user_id, scores[user_id])
	_values.clear()
	for key: Variant in current_values:
		if key is String:
			_values[key] = current_values[key]
			value_changed.emit(key)
	_set_phase(current_phase, current_time_left)

@rpc("authority", "call_remote", "reliable")
func _set_phase(new_phase: StringName, duration: float) -> void:
	phase = new_phase
	time_left = maxf(duration, 0.0)
	_has_timer = time_left > 0.0
	phase_changed.emit(phase)

@rpc("authority", "call_remote", "reliable")
func _set_score(user_id: int, score: int) -> void:
	scores[user_id] = score
	score_changed.emit(user_id, score)

@rpc("authority", "call_remote", "reliable")
func _set_value(key: String, value: Variant) -> void:
	if value == null:
		_values.erase(key)
	else:
		_values[key] = value
	value_changed.emit(key)
