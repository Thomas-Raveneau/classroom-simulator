extends LobbyGameTest
## NetworkAnimation over a real connection: what the owner of an object plays is played
## on every other player, through the replication of the object.

func _pawn(viewer: LobbyTestPeer, owner_peer: LobbyTestPeer) -> LobbyTestPawn:
	var scene: LobbyTestGameScene = scene_of(viewer)
	return scene.get_pawn(owner_peer.service.local_member.peer_id) if scene != null else null

func _plays(viewer: LobbyTestPeer, owner_peer: LobbyTestPeer, animation: StringName) -> Callable:
	return func() -> bool:
		var pawn: LobbyTestPawn = _pawn(viewer, owner_peer)
		return pawn != null and pawn.animation_player.current_animation == animation

func test_animation_of_a_player_is_played_on_the_others() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var other: LobbyTestPeer = await add_client()
	await start_game(host)
	await until(func() -> bool: return _pawn(client, client) != null, "client has its pawn")
	_pawn(client, client).animation_player.play(&"idle")
	await until(_plays(host, client, &"idle"), "host sees the animation of the client")
	await until(_plays(other, client, &"idle"), "another client sees it too")
	assert_false(_pawn(other, host).animation_player.is_playing(), "the pawn of the host plays nothing")
	_pawn(host, host).animation_player.play(&"idle")
	await until(_plays(client, host, &"idle"), "client sees the animation of the host")
	assert_engine_error_count(0)

func test_animation_started_again_is_played_again() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	await until(func() -> bool: return _pawn(client, client) != null, "client has its pawn")
	var starts: Array[StringName] = []
	await until(func() -> bool: return _pawn(host, client) != null, "host has the pawn of the client")
	_pawn(host, client).animation_player.animation_started.connect(
		func(animation: StringName) -> void: starts.append(animation)
	)
	var own_player: AnimationPlayer = _pawn(client, client).animation_player
	own_player.play(&"wave")
	await until(func() -> bool: return starts.size() == 1, "host plays it once")
	await until(func() -> bool: return not own_player.is_playing(), "it ended on the client")
	own_player.play(&"wave")
	await until(func() -> bool: return starts.size() == 2, "host plays it a second time")
	assert_eq(starts, [&"wave", &"wave"])

func test_player_joining_in_progress_sees_what_is_playing() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	await until(func() -> bool: return _pawn(client, client) != null, "client has its pawn")
	_pawn(client, client).animation_player.play(&"idle")
	await until(_plays(host, client, &"idle"), "host sees the animation of the client")
	await wait_seconds(0.5)
	var late: LobbyTestPeer = await add_client()
	await until(func() -> bool: return late.service.state == LobbyTypes.State.IN_GAME, "late player is in game")
	await until(_plays(late, client, &"idle"), "it sees an animation started before it came")
	assert_false(_pawn(late, host).animation_player.is_playing(), "and nothing where nothing plays")
	assert_engine_error_count(0)

func test_animations_follow_on_a_bad_connection() -> void:
	conditions = NetworkConditions.new()
	conditions.latency_ms = 150
	conditions.jitter_ms = 40
	conditions.loss_percent = 10.0
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var other: LobbyTestPeer = await add_client()
	await start_game(host)
	await until(func() -> bool: return _pawn(client, client) != null, "client has its pawn")
	var own_player: AnimationPlayer = _pawn(client, client).animation_player
	for animation: StringName in [&"idle", &"wave", &"idle"]:
		own_player.play(animation)
		await until(_plays(host, client, animation), "host sees %s" % animation)
		await until(_plays(other, client, animation), "another client sees %s" % animation)
