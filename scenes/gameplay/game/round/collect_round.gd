class_name CollectRound
extends Node
## A first, deliberately basic game to replace with the real one: after a countdown,
## players collect the coins the host spawns until the time is over, then the ranking is
## shown and everyone goes back to the lobby.
##
## It shows how the network bricks fit together:
## - MatchState carries the phase, the timer and the scores to every player;
## - NetworkSpawner makes the coins appear and disappear on every player;
## - HostActions lets a player ask for a coin, and the host decide.

const COLLECT_ACTION: StringName = &"collect"

@export var match_state: MatchState
@export var actions: HostActions
@export var coin_spawner: NetworkSpawner
@export var player_spawner: PlayerSpawner
@export var coin_scene: PackedScene

@export_group("Rules")
@export var countdown_seconds: float = 3.0
@export var round_seconds: float = 60.0
@export var results_seconds: float = 8.0
@export var max_coins: int = 8
## Time between two coins, in seconds.
@export var coin_interval: float = 1.0
## Coins appear within this distance of the center of the map, on each axis.
@export var coin_area_extent: float = 9.0
## How close to a coin the host must see the character of a player to grant it.
@export var collect_distance: float = 3.0

var _next_coin_in: float = 0.0

func _ready() -> void:
	# Declared on every player; only the host runs the two functions.
	actions.register(COLLECT_ACTION, _can_collect, _collect)
	if not multiplayer.is_server():
		return
	match_state.phase_time_elapsed.connect(_on_phase_time_elapsed)
	Lobby.game_started.connect(_start_countdown)

func _process(delta: float) -> void:
	if not multiplayer.is_server() or match_state.phase != MatchState.PHASE_PLAYING:
		return
	_next_coin_in -= delta
	if _next_coin_in <= 0.0 and _get_coins().get_child_count() < max_coins:
		_next_coin_in = coin_interval
		var position: Vector3 = Vector3(
			randf_range(-coin_area_extent, coin_area_extent), 1.0,
			randf_range(-coin_area_extent, coin_area_extent)
		)
		coin_spawner.spawn_scene(coin_scene, { "position": position })

func _start_countdown() -> void:
	match_state.reset_scores()
	match_state.start_phase(MatchState.PHASE_COUNTDOWN, countdown_seconds)

func _on_phase_time_elapsed(phase: StringName) -> void:
	match phase:
		MatchState.PHASE_COUNTDOWN:
			match_state.start_phase(MatchState.PHASE_PLAYING, round_seconds)
		MatchState.PHASE_PLAYING:
			for coin: Node in _get_coins().get_children():
				coin.queue_free()
			match_state.start_phase(MatchState.PHASE_RESULTS, results_seconds)
		MatchState.PHASE_RESULTS:
			Lobby.return_to_lobby()

## Host: may this player take this coin? The arguments come from another machine.
func _can_collect(member: LobbyMember, arguments: Array) -> bool:
	if match_state.phase != MatchState.PHASE_PLAYING:
		return false
	if arguments.size() != 1 or arguments[0] is not String:
		return false
	var coin: Coin = _find_coin(arguments[0])
	var player: Player = player_spawner.get_player(member.peer_id)
	if coin == null or player == null or coin.is_queued_for_deletion():
		return false
	return player.global_position.distance_to(coin.global_position) <= collect_distance

## Host: the coin disappears for everyone (NetworkSpawner) and the score reaches
## everyone (MatchState).
func _collect(member: LobbyMember, arguments: Array) -> void:
	_find_coin(arguments[0]).queue_free()
	match_state.add_score(member.user_id)

func _get_coins() -> Node:
	return coin_spawner.get_node(coin_spawner.spawn_path)

func _find_coin(coin_name: String) -> Coin:
	# has_node() on a plain child name: a path sent by a player cannot reach anything else.
	if coin_name.contains("/") or not _get_coins().has_node(coin_name):
		return null
	return _get_coins().get_node(coin_name) as Coin
