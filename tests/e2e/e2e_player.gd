extends Node
## Autopilot of an end-to-end run: plays one role (host, client or late joiner) in the
## real game, through the real autoloads and scenes, and quits with a non-zero exit code
## when something is not as expected. See tests/e2e/run.sh.
##
## The three players coordinate through their lobby member data: each sets a flag when
## it finished a step, and waits for everyone's flag before the next one.

const ROLE_ARGUMENT: String = "--e2e-role="
const TIMEOUT: float = 20.0
## Where each role moves its own character, to check that positions are synchronized.
const TARGET_X: Dictionary[String, float] = { "host": 7.0, "client": -7.0, "late": 3.0 }
const EXPECTED_PLAYERS: int = 3

var _role: String = ""

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ROLE_ARGUMENT):
			_role = argument.trim_prefix(ROLE_ARGUMENT)
	# Moved out of the scene it started in, to survive the scene changes of the game.
	reparent.call_deferred(get_tree().root)
	Lobby.config.allow_join_in_progress = true
	Lobby.left.connect(func(reason: LobbyTypes.Reason) -> void: _log("left: %s" % _reason(reason)))
	Lobby.join_failed.connect(func(reason: LobbyTypes.Reason) -> void: _log("join failed: %s" % _reason(reason)))
	Lobby.state_changed.connect(
		func(state: LobbyTypes.State) -> void: _log("state: %s" % LobbyTypes.State.find_key(state))
	)
	await get_tree().process_frame
	match _role:
		"host": await _play_host()
		"client": await _play_client()
		"late": await _play_late()
		_: _fail("unknown role '%s'" % _role)
	_log("OK")
	get_tree().quit(0)

# --- Roles -------------------------------------------------------------------------------

func _play_host() -> void:
	Lobby.create()
	await _until(Lobby.is_host, "lobby created")
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.members.size() == 2, "client joined")
	await _until(Lobby.are_all_ready, "client ready")
	_check(Lobby.start_game(), "game started")
	await _until_scene(Lobby.config.game_scene)
	# The round only ends when this script says so, and results are short.
	_round().round_seconds = 600.0
	_round().results_seconds = 2.0
	await _play_game()
	# The round ended by itself: results, then everyone back to the lobby.
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_LOBBY, "everyone is back in the lobby")
	_check(Lobby.can_start_game(), "can start again")
	_check(Lobby.members.size() == EXPECTED_PLAYERS, "everyone came back")
	Lobby.kick(_member_named("Late"))
	await _until(func() -> bool: return Lobby.members.size() == 2, "late player kicked")
	await get_tree().create_timer(1.0).timeout
	Lobby.leave()
	await _until_scene(Lobby.config.main_menu_scene)

func _play_client() -> void:
	# The three instances start together: asks again when the host was not up yet.
	await _until(
		func() -> bool:
			if Lobby.state == LobbyTypes.State.NONE:
				Lobby.join(0)
			return Lobby.is_in_lobby(),
		"joined"
	)
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.is_host(), "not host")
	_check(Lobby.get_member(1).name == "Host", "knows the host by name")
	Lobby.set_ready(true)
	await _play_game()
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.local_member.is_ready, "ready flag cleared")
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "lobby closed")
	_check(Lobby.last_reason == LobbyTypes.Reason.HOST_LEFT, "told that the host left")
	_check(not Lobby.can_rejoin(), "nothing to rejoin")
	await _until_scene(Lobby.config.main_menu_scene)

func _play_late() -> void:
	# Joins once the game is running, found by asking again until the host admits.
	while Lobby.state != LobbyTypes.State.IN_GAME:
		if Lobby.state == LobbyTypes.State.NONE:
			await get_tree().create_timer(2.5).timeout
			Lobby.join(0)
		await get_tree().create_timer(0.2).timeout
	_check(get_tree().current_scene.scene_file_path == Lobby.config.game_scene, "loaded the game directly")
	await _play_game()
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "removed from the lobby")
	_check(Lobby.last_reason == LobbyTypes.Reason.KICKED, "told about the kick")
	await _until_scene(Lobby.config.main_menu_scene)

# --- The game, step by step --------------------------------------------------------------

func _play_game() -> void:
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_GAME, "in game")
	await _until(func() -> bool: return _players().size() == EXPECTED_PLAYERS, "every character is spawned")
	await _check_positions()
	await _everyone_did("positions")
	await _fall_and_respawn()
	await _collect_a_coin()
	await _everyone_did("coins")
	await _lose_and_recover_the_client()
	await _everyone_did("reconnection")
	if _role == "host":
		_match_state().start_phase(MatchState.PHASE_PLAYING, 0.5)
	await _until(func() -> bool: return _match_state().phase == MatchState.PHASE_RESULTS, "results are shown")

## Everyone sees every character, named, where its owner put it and animated as there.
func _check_positions() -> void:
	var own_player: Player = _own_player()
	_check(own_player != null and own_player.is_multiplayer_authority(), "controls its own character")
	own_player.position.x = TARGET_X[_role]
	for player_name: String in ["Host", "Client", "Late"]:
		var target_x: float = TARGET_X[player_name.to_lower()]
		await _until(
			func() -> bool:
				var player: Player = _player_of(_member_named(player_name))
				return player != null and absf(player.position.x - target_x) < 0.5,
			"sees %s at its place" % player_name
		)
		# Only the owner of a character animates it: the others play what it publishes.
		await _until(
			func() -> bool:
				var player: Player = _player_of(_member_named(player_name))
				return player != null and _animation_of(player) == &"idle",
			"sees %s standing still" % player_name
		)

## Falling off the map: the host puts the character back on a spawn point.
func _fall_and_respawn() -> void:
	_own_player().position.y = -50.0
	await _until(func() -> bool: return _own_player().position.y > -5.0, "respawned after falling")

## Collecting is asked to the host, and the scores it keeps reach everyone.
func _collect_a_coin() -> void:
	await _until(func() -> bool: return _match_state().phase == MatchState.PHASE_PLAYING, "the round is running")
	var own_user_id: int = Lobby.local_member.user_id
	await _until(
		func() -> bool:
			var coins: Node = get_tree().current_scene.get_node("Coins")
			if _match_state().get_score(own_user_id) == 0 and coins.get_child_count() > 0:
				# Walks onto a coin, the fast way.
				_own_player().position = (coins.get_child(0) as Node3D).position
			return _match_state().get_score(own_user_id) > 0,
		"collected a coin"
	)
	await _until(
		func() -> bool:
			return Lobby.members.size() == EXPECTED_PLAYERS and Lobby.get_members().all(
				func(member: LobbyMember) -> bool: return _match_state().get_score(member.user_id) > 0
			),
		"sees a score for everyone"
	)

## The client loses its connection in the middle of the game, and comes back to its seat.
func _lose_and_recover_the_client() -> void:
	# Everyone says it is past the previous step: the host only cuts once all have, or it
	# would cut players still waiting for each other.
	Lobby.set_member_data("e2e_ready_for_cut", true)
	match _role:
		"host":
			await _until(
				func() -> bool:
					return Lobby.members.size() == EXPECTED_PLAYERS and Lobby.get_members().all(
						func(member: LobbyMember) -> bool: return member.data.get("e2e_ready_for_cut") == true
					),
				"everyone is ready for the cut"
			)
			# As a network failure would: the host just finds the member gone.
			Lobby._member_sync.drop(_member_named("Client").peer_id)
			_check(Lobby.get_absent_members().size() == 1, "keeps the seat of the client")
			await _until(
				func() -> bool: return Lobby.get_absent_members().is_empty() and Lobby.members.size() == EXPECTED_PLAYERS,
				"the client took its seat back"
			)
		"client":
			var own_user_id: int = Lobby.local_member.user_id
			await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "lost the connection")
			_check(Lobby.last_reason == LobbyTypes.Reason.CONNECTION_LOST, "told that the connection was lost")
			_check(Lobby.can_rejoin(), "can rejoin")
			Lobby.rejoin()
			await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_GAME, "back in the game")
			await _until(func() -> bool: return _own_player() != null, "has a character again")
			_check(Lobby.local_member.data.get("e2e_coins") == true, "member data is restored")
			await _until(func() -> bool: return _match_state().get_score(own_user_id) > 0, "kept its score")
	await _until(func() -> bool: return _players().size() == EXPECTED_PLAYERS, "every character is there again")

## Tells the others this step is done, and waits until they all are.
func _everyone_did(step: String) -> void:
	var key: String = "e2e_%s" % step
	Lobby.set_member_data(key, true)
	await _until(
		func() -> bool:
			return Lobby.members.size() == EXPECTED_PLAYERS and Lobby.get_members().all(
				func(member: LobbyMember) -> bool: return member.data.get(key) == true
			),
		"everyone finished: %s" % step
	)

# --- Helpers -----------------------------------------------------------------------------

func _round() -> CollectRound:
	return get_tree().current_scene.get_node("CollectRound") as CollectRound

func _match_state() -> MatchState:
	return get_tree().current_scene.get_node("MatchState") as MatchState

func _players() -> Array[Node]:
	var scene: Node = get_tree().current_scene
	var container: Node = scene.get_node_or_null("Players") if scene != null else null
	return container.get_children() if container != null else []

func _own_player() -> Player:
	return _player_of(Lobby.local_member)

func _player_of(member: LobbyMember) -> Player:
	if member != null:
		for player: Node in _players():
			if player.name == str(member.peer_id):
				return player as Player
	return null

func _animation_of(player: Player) -> StringName:
	return (player.get_node("AnimationPlayer") as AnimationPlayer).assigned_animation

func _member_named(member_name: String) -> LobbyMember:
	for member: LobbyMember in Lobby.get_members():
		if member.name == member_name:
			return member
	return null

func _until_scene(path: String) -> void:
	await _until(
		func() -> bool:
			var scene: Node = get_tree().current_scene
			return scene != null and scene.scene_file_path == path,
		"shows %s" % path.get_file()
	)

func _until(condition: Callable, what: String) -> void:
	var elapsed: float = 0.0
	while not condition.call():
		if elapsed > TIMEOUT:
			for player: Node in _players():
				_log("  %s is at %s" % [player.name, (player as Player).position])
			_fail("timeout waiting for: %s" % what)
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_log("ok: %s (%.2fs)" % [what, elapsed])

func _check(condition: bool, what: String) -> void:
	if condition:
		_log("ok: %s" % what)
	else:
		_fail(what)

func _fail(what: String) -> void:
	_log("FAILED: %s" % what)
	get_tree().quit(1)
	# Nothing else may run after a failure.
	set_process(false)
	await get_tree().create_timer(60.0).timeout

func _reason(reason: LobbyTypes.Reason) -> String:
	return LobbyTypes.Reason.find_key(reason)

func _log(text: String) -> void:
	print("[e2e %s %6.2fs] %s" % [_role, Time.get_ticks_msec() / 1000.0, text])
