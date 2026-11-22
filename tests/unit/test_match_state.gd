extends LobbyGameTest

func _state(test_peer: LobbyTestPeer) -> MatchState:
	return scene_of(test_peer).match_state

func test_phase_and_timer_reach_every_player() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	watch_signals(_state(client))
	_state(host).start_phase(MatchState.PHASE_PLAYING, 30.0)
	await until(func() -> bool: return _state(client).phase == MatchState.PHASE_PLAYING, "client is in the phase")
	assert_signal_emitted_with_parameters(_state(client), "phase_changed", [MatchState.PHASE_PLAYING])
	assert_almost_eq(_state(client).time_left, 30.0, 1.0)
	var before: float = _state(client).time_left
	await wait_seconds(0.5)
	assert_lt(_state(client).time_left, before, "the timer counts down on the client")

func test_host_is_told_when_the_phase_time_is_over() -> void:
	var host: LobbyTestPeer = await add_host()
	await start_game(host)
	watch_signals(_state(host))
	_state(host).start_phase(MatchState.PHASE_COUNTDOWN, 0.3)
	await wait_for_signal(_state(host).phase_time_elapsed, WAIT)
	assert_signal_emitted_with_parameters(_state(host), "phase_time_elapsed", [MatchState.PHASE_COUNTDOWN])
	assert_eq(_state(host).time_left, 0.0)
	await wait_seconds(0.2)
	assert_signal_emit_count(_state(host), "phase_time_elapsed", 1)

func test_scores_and_values_reach_every_player() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	var client_user_id: int = client.service.local_member.user_id
	_state(host).add_score(client_user_id, 2)
	_state(host).add_score(client_user_id)
	_state(host).set_score(host.service.local_member.user_id, 1)
	_state(host).set_value("map", "forest")
	# Sent in that order: once the last one arrived, the others did.
	await until(func() -> bool: return _state(client).get_value("map") == "forest", "client knows the map")
	assert_eq(_state(client).get_score(client_user_id), 3)
	assert_eq(_state(client).get_score(host.service.local_member.user_id), 1)
	assert_eq(_state(client).get_ranking()[0], client_user_id, "best score first")
	_state(host).reset_scores()
	_state(host).set_value("map", null)
	await until(func() -> bool: return _state(client).get_score(client_user_id) == 0, "scores are reset")
	await until(func() -> bool: return _state(client).get_value("map") == null, "the value is erased")

func test_only_the_host_writes() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	_state(client).start_phase(MatchState.PHASE_RESULTS)
	_state(client).set_score(1, 99)
	_state(client).set_value("map", "hacked")
	await wait_seconds(0.3)
	for test_peer: LobbyTestPeer in [host, client]:
		assert_eq(_state(test_peer).phase, MatchState.PHASE_WAITING)
		assert_eq(_state(test_peer).get_score(1), 0)
		assert_null(_state(test_peer).get_value("map"))

func test_player_joining_in_progress_receives_the_whole_state() -> void:
	var host: LobbyTestPeer = await add_host()
	await start_game(host)
	_state(host).start_phase(MatchState.PHASE_PLAYING, 20.0)
	_state(host).set_score(77, 5)
	_state(host).set_value("map", "forest")
	var late: LobbyTestPeer = add_peer()
	late.loader.manual = true
	late.service.join(0)
	await until(func() -> bool: return late.service.state == LobbyTypes.State.LOADING, "late player is loading")
	# Changes made while the late player has no scene must not be sent to it.
	_state(host).set_score(77, 6)
	await wait_seconds(0.3)
	late.loader.complete()
	await until(func() -> bool: return scene_of(late) != null and _state(late).phase == MatchState.PHASE_PLAYING, "late player has the phase")
	assert_eq(_state(late).get_score(77), 6)
	assert_eq(_state(late).get_player_name(host.service.local_member.user_id), host.service.local_member.name)
	assert_eq(
		_state(host).get_player_name(late.service.local_member.user_id), late.service.local_member.name,
		"the late player is known by name"
	)
	assert_eq(_state(late).get_value("map"), "forest")
	assert_between(_state(late).time_left, 15.0, 20.0)
	_state(host).set_score(77, 7)
	await until(func() -> bool: return _state(late).get_score(77) == 7, "later changes keep coming")
	assert_engine_error_count(0)

func test_state_set_when_the_game_starts_arrives_once() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	# As a game does: the host starts the first phase the moment everyone is in.
	host.service.game_started.connect(
		func() -> void: scene_of(host).match_state.start_phase(MatchState.PHASE_COUNTDOWN, 3.0)
	)
	var phases_seen: Array[StringName] = []
	client.loader.changed.connect(
		func(_path: String) -> void:
			if scene_of(client) != null:
				scene_of(client).match_state.phase_changed.connect(phases_seen.append)
	)
	await start_game(host)
	await until(func() -> bool: return _state(client).phase == MatchState.PHASE_COUNTDOWN, "client has the phase")
	await wait_seconds(0.2)
	assert_eq(phases_seen.size(), 1, "the phase is announced once, not twice")

func test_players_who_left_keep_their_name_and_score() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var other: LobbyTestPeer = await add_client()
	await start_game(host)
	var client_user_id: int = client.service.local_member.user_id
	var client_name: String = client.service.local_member.name
	_state(host).add_score(client_user_id, 4)
	await until(func() -> bool: return _state(other).get_score(client_user_id) == 4, "score is known")
	client.service.leave()
	await until(func() -> bool: return other.service.members.size() == 2, "the client is gone")
	assert_eq(_state(other).get_player_name(client_user_id), client_name)
	assert_eq(_state(other).get_score(client_user_id), 4)
	assert_true(_state(other).get_ranking().has(client_user_id))
