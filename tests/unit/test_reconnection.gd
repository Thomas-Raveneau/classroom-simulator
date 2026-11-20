extends LobbyGameTest
## A player who loses its connection during a game keeps its seat for a while and can
## come back to it, with its data and its score.

func before_each() -> void:
	super()
	config.allow_join_in_progress = false
	config.reconnect_grace = 5.0

func _in_game(test_peer: LobbyTestPeer) -> Callable:
	return func() -> bool: return test_peer.service.state == LobbyTypes.State.IN_GAME

func test_disconnected_player_comes_back_with_its_data_and_score() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	client.service.set_member_data("team", 2)
	await start_game(host)
	var user_id: int = client.service.local_member.user_id
	var old_peer_id: int = client.service.local_member.peer_id
	scene_of(host).match_state.add_score(user_id, 3)
	watch_signals(client.service)
	await cut_connection(host, client)
	assert_signal_emitted_with_parameters(client.service, "left", [LobbyTypes.Reason.CONNECTION_LOST])
	assert_true(client.service.can_rejoin())
	await until(func() -> bool: return host.service.members.size() == 1, "host removed the member")
	var absent_members: Array[LobbyMember] = host.service.get_absent_members()
	assert_eq(absent_members.size(), 1, "its seat is kept")
	assert_eq(absent_members[0].user_id, user_id)
	assert_null(scene_of(host).get_pawn(old_peer_id), "its pawn is gone meanwhile")

	client.service.rejoin()
	await until(_in_game(client), "client is back in the game")
	var new_peer_id: int = client.service.local_member.peer_id
	assert_eq(host.service.members.size(), 2)
	assert_eq(host.service.get_absent_members().size(), 0, "the seat is taken back")
	assert_eq(client.service.local_member.data.get("team"), 2, "its data is restored")
	assert_eq(host.service.get_member(new_peer_id).data.get("team"), 2)
	await until(func() -> bool: return scene_of(client).get_pawn(new_peer_id) != null, "it has a pawn again")
	assert_not_null(scene_of(host).get_pawn(new_peer_id))
	assert_eq(scene_of(client).match_state.get_score(user_id), 3, "its score survived")
	assert_false(client.service.can_rejoin(), "nothing more to rejoin")
	assert_engine_error_count(0)

func test_locked_game_only_admits_the_holder_of_a_seat() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	await cut_connection(host, client)
	var stranger: LobbyTestPeer = await add_client()
	assert_eq(stranger.service.last_reason, LobbyTypes.Reason.GAME_IN_PROGRESS)
	client.service.rejoin()
	await until(_in_game(client), "the seat holder is admitted")

func test_reserved_seat_counts_as_taken() -> void:
	config.allow_join_in_progress = true
	config.max_players = 2
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	await cut_connection(host, client)
	var stranger: LobbyTestPeer = await add_client()
	assert_eq(stranger.service.last_reason, LobbyTypes.Reason.LOBBY_FULL)
	client.service.rejoin()
	await until(_in_game(client), "its own seat does not count against it")

func test_player_leaving_on_purpose_keeps_no_seat() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	client.service.leave()
	await until(func() -> bool: return host.service.members.size() == 1, "host removed the member")
	assert_eq(host.service.get_absent_members().size(), 0)
	assert_false(client.service.can_rejoin())

func test_kicked_player_keeps_no_seat() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	host.service.kick(host.service.get_member(client.service.local_member.peer_id))
	await until(func() -> bool: return host.service.members.size() == 1, "host removed the member")
	assert_eq(host.service.get_absent_members().size(), 0)
	assert_false(client.service.can_rejoin())

func test_seat_is_released_after_the_grace_time() -> void:
	config.reconnect_grace = 0.5
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	watch_signals(host.service)
	await cut_connection(host, client)
	await until(func() -> bool: return host.service.get_absent_members().size() == 1, "seat is kept at first")
	await until(func() -> bool: return host.service.get_absent_members().is_empty(), "seat is released")
	assert_signal_emit_count(host.service, "absent_members_changed", 2)
	await until(func() -> bool: return not client.service.can_rejoin(), "rejoin is no longer offered")
	client.service.join(0)
	await until(func() -> bool: return client.service.state == LobbyTypes.State.NONE, "too late")
	assert_eq(client.service.last_reason, LobbyTypes.Reason.GAME_IN_PROGRESS)

func test_no_seat_outside_of_a_game() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await cut_connection(host, client)
	await until(func() -> bool: return host.service.members.size() == 1, "host removed the member")
	assert_eq(host.service.get_absent_members().size(), 0)
	assert_eq(client.service.last_reason, LobbyTypes.Reason.CONNECTION_LOST)
	assert_false(client.service.can_rejoin(), "it can simply join again")

func test_seats_are_cleared_when_the_game_ends() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	await cut_connection(host, client)
	await until(func() -> bool: return host.service.get_absent_members().size() == 1, "seat is kept")
	host.service.return_to_lobby()
	assert_eq(host.service.get_absent_members().size(), 0)

func test_host_leaving_is_not_a_connection_loss() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	host.service.leave()
	await until(func() -> bool: return client.service.state == LobbyTypes.State.NONE, "client is out")
	assert_eq(client.service.last_reason, LobbyTypes.Reason.HOST_LEFT)
	assert_false(client.service.can_rejoin())

func test_player_back_on_a_new_connection_replaces_its_stale_one() -> void:
	# The player comes back before the host noticed that its first connection is dead.
	config.connection_timeout = 1.5
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	client.service.set_member_data("team", 2)
	await start_game(host)
	var old_peer_id: int = client.service.local_member.peer_id
	# The first connection goes silent, and the same user connects again right away.
	client.service.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var twin: LobbyTestPeer = add_peer()
	twin.backend._identity = client.backend.get_local_identity()
	twin.service.join(0)
	await until(_in_game(twin), "the new connection is admitted")
	assert_eq(host.service.members.size(), 2, "the stale connection is replaced, not kept beside")
	assert_null(host.service.get_member(old_peer_id))
	assert_eq(host.service.get_absent_members().size(), 0, "no seat is left behind")
	assert_eq(twin.service.local_member.data.get("team"), 2, "with what the player had")
	await until(func() -> bool: return scene_of(host).pawns.get_child_count() == 2, "one pawn per player")
	assert_engine_error_count(0)

func test_member_that_stops_answering_is_dropped_and_can_come_back() -> void:
	config.connection_timeout = 0.6
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	# The network of the client goes silent: its connection stays open but nothing moves.
	client.service.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await until(func() -> bool: return host.service.members.size() == 1, "host dropped the silent member")
	assert_eq(host.service.get_absent_members().size(), 1, "and kept its seat")
	await until(func() -> bool: return client.service.state == LobbyTypes.State.NONE, "client noticed too")
	assert_eq(client.service.last_reason, LobbyTypes.Reason.CONNECTION_LOST)
	client.service.rejoin()
	await until(_in_game(client), "client is back in the game")
