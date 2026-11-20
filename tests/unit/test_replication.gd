extends GutTest
## Real spawner / synchronizer replication between players of the same process, to
## validate that NetworkSpawner and ReplicationGate make joining in progress safe.

const GAME_SCENE: String = "res://game.tscn"
const LOBBY_SCENE: String = "res://lobby.tscn"
const WAIT: float = 3.0

var _config: LobbyConfig
var _port: int
var _peers: Array[LobbyTestPeer]

func before_each() -> void:
	_config = LobbyConfig.new()
	_config.join_timeout = 2.0
	_config.load_timeout = 5.0
	_config.game_scene = GAME_SCENE
	_config.lobby_scene = LOBBY_SCENE
	_config.dismiss_grace = 0.3
	_config.allow_join_in_progress = true
	_port = LobbyTestPeer.pick_port()
	_peers = []

func after_each() -> void:
	for test_peer: LobbyTestPeer in _peers:
		test_peer.shutdown()
	_peers.clear()

func _add_peer() -> LobbyTestPeer:
	var test_peer: LobbyTestPeer = LobbyTestPeer.create(self, _config, _port)
	test_peer.loader.scene_factory = func(path: String) -> Node:
		return LobbyTestGameScene.new() if path == GAME_SCENE else Node.new()
	_peers.append(test_peer)
	return test_peer

func _add_host() -> LobbyTestPeer:
	var host: LobbyTestPeer = _add_peer()
	host.service.create()
	await wait_for_signal(host.service.created, WAIT)
	return host

func _add_client() -> LobbyTestPeer:
	var client: LobbyTestPeer = _add_peer()
	client.service.join(0)
	await wait_until(func() -> bool: return client.service.state != LobbyTypes.State.JOINING, WAIT)
	return client

func _scene(test_peer: LobbyTestPeer) -> LobbyTestGameScene:
	return test_peer.loader.current_scene as LobbyTestGameScene

func _pawn_count(test_peer: LobbyTestPeer) -> int:
	return _scene(test_peer).pawns.get_child_count() if _scene(test_peer) != null else 0

func _until(condition: Callable, text: String) -> void:
	await wait_until(condition, WAIT)
	assert_true(condition.call(), text)

func _pawn_value_is(viewer: LobbyTestPeer, owner_peer: LobbyTestPeer, value: int) -> Callable:
	return func() -> bool:
		var pawn: LobbyTestPawn = _scene(viewer).get_pawn(owner_peer.service.local_member.peer_id)
		return pawn != null and pawn.value == value

func _set_own_pawn_value(test_peer: LobbyTestPeer, value: int) -> void:
	_scene(test_peer).get_pawn(test_peer.service.local_member.peer_id).value = value

func test_pawns_are_spawned_and_synchronized_at_game_start() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	# The client loads later than the host: nothing may reach it before.
	client.loader.manual = true
	host.service.start_game()
	await wait_seconds(0.3)
	assert_eq(_pawn_count(host), 0, "nothing is spawned before everyone has loaded")
	client.loader.complete()
	await _until(func() -> bool: return _pawn_count(client) == 2, "client has both pawns")
	assert_eq(_pawn_count(host), 2)
	_set_own_pawn_value(client, 5)
	_set_own_pawn_value(host, 6)
	await _until(_pawn_value_is(host, client, 5), "host receives the value of the client")
	await _until(_pawn_value_is(client, host, 6), "client receives the value of the host")
	assert_engine_error_count(0)

func test_player_joining_in_progress_gets_everything() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(client) == 2, "client has both pawns")
	_set_own_pawn_value(client, 5)
	await _until(_pawn_value_is(host, client, 5), "host receives the value of the client")

	var late: LobbyTestPeer = _add_peer()
	late.loader.manual = true
	late.service.join(0)
	await _until(
		func() -> bool: return late.service.state == LobbyTypes.State.LOADING,
		"late player is loading"
	)
	# Connected for a while without the scene: the others keep replicating between them.
	_set_own_pawn_value(client, 7)
	await _until(_pawn_value_is(host, client, 7), "replication goes on while the late player loads")
	await wait_seconds(0.3)
	assert_eq(_pawn_count(host), 2, "no pawn for the late player yet")

	late.loader.complete()
	await _until(func() -> bool: return _pawn_count(late) == 3, "late player has every pawn")
	await _until(func() -> bool: return _pawn_count(client) == 3, "client has the pawn of the late player")
	assert_eq(_pawn_count(host), 3)
	# Synchronizers owned by players work in every direction with the late player.
	await _until(_pawn_value_is(late, client, 7), "late player receives the current value of the client")
	_set_own_pawn_value(client, 8)
	_set_own_pawn_value(host, 9)
	_set_own_pawn_value(late, 10)
	await _until(_pawn_value_is(late, client, 8), "late player receives updates of the client")
	await _until(_pawn_value_is(late, host, 9), "late player receives updates of the host")
	await _until(_pawn_value_is(client, late, 10), "client receives updates of the late player")
	await _until(_pawn_value_is(host, late, 10), "host receives updates of the late player")
	assert_engine_error_count(0)

func test_spawned_object_gets_properties_name_and_gate() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(client) == 2, "client has both pawns")
	var scene: LobbyTestGameScene = _scene(host)
	var spawned: Node = scene.spawner.spawn_scene(scene.pawn_scene, { "value": 42 }, 1, "Extra")
	assert_eq(spawned.name, &"Extra")
	await _until(func() -> bool: return _scene(client).pawns.has_node("Extra"), "client received the object")
	var received: LobbyTestPawn = _scene(client).pawns.get_node("Extra") as LobbyTestPawn
	assert_eq(received.value, 42, "properties are applied on every player")
	assert_true(received.has_node("ReplicationGate"), "a gate was added")
	assert_null(_scene(client).spawner.spawn_scene(scene.pawn_scene), "a client cannot spawn")
	assert_push_error("only the host can spawn")
	spawned.queue_free()
	await _until(func() -> bool: return not _scene(client).pawns.has_node("Extra"), "freed everywhere")

func test_object_of_the_scene_reaches_a_player_joining_in_progress() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	# The host loads first and its beacon changes while the client has no scene yet.
	client.loader.manual = true
	host.service.start_game()
	await wait_seconds(0.2)
	_scene(host).beacon.value = 1
	await wait_seconds(0.2)
	client.loader.complete()
	await _until(func() -> bool: return _scene(client) != null and _scene(client).beacon.value == 1, "client receives the beacon")
	var late: LobbyTestPeer = _add_peer()
	late.loader.manual = true
	late.service.join(0)
	await _until(func() -> bool: return late.service.state == LobbyTypes.State.LOADING, "late player is loading")
	_scene(host).beacon.value = 2
	await wait_seconds(0.3)
	late.loader.complete()
	await _until(func() -> bool: return _scene(late) != null and _scene(late).beacon.value == 2, "late player receives the beacon")
	_scene(host).beacon.value = 3
	await _until(func() -> bool: return _scene(late).beacon.value == 3 and _scene(client).beacon.value == 3, "updates keep flowing")
	assert_engine_error_count(0)

func test_object_owned_by_a_leaving_player_is_removed() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(client) == 2, "client has both pawns")
	var scene: LobbyTestGameScene = _scene(host)
	scene.spawner.spawn_scene(scene.pawn_scene, {}, client.service.local_member.peer_id, "Owned")
	scene.spawner.spawn_scene(scene.pawn_scene, {}, 1, "Kept")
	client.service.leave()
	await _until(func() -> bool: return not scene.pawns.has_node("Owned"), "what the client owned is freed")
	assert_true(scene.pawns.has_node("Kept"), "what the host owns stays")

func test_pawn_of_a_leaving_player_is_removed_everywhere() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(other) == 3, "everyone is spawned")
	client.service.leave()
	await _until(func() -> bool: return _pawn_count(host) == 2, "host removed the pawn")
	await _until(func() -> bool: return _pawn_count(other) == 2, "other client removed the pawn")
	assert_engine_error_count(0)

## Players keep synchronizing their pawns every frame: leaving the game scene must not
## let an update reach a player who does not have the scene anymore.
func _keep_pawns_moving(test_peers: Array[LobbyTestPeer], frames: int) -> void:
	for frame: int in frames:
		for test_peer: LobbyTestPeer in test_peers:
			var scene: LobbyTestGameScene = _scene(test_peer)
			if scene != null and test_peer.service.local_member != null:
				var pawn: LobbyTestPawn = scene.get_pawn(test_peer.service.local_member.peer_id)
				if pawn != null:
					pawn.value += 1
		await wait_process_frames(1)

func test_return_to_lobby_stops_replication_cleanly() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	var everyone: Array[LobbyTestPeer] = [host, client, other]
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(other) == 3, "everyone is spawned")
	await _keep_pawns_moving(everyone, 10)
	host.service.return_to_lobby()
	await _keep_pawns_moving(everyone, 30)
	for test_peer: LobbyTestPeer in everyone:
		await _until(
			func() -> bool: return test_peer.service.state == LobbyTypes.State.IN_LOBBY,
			"player is back in the lobby"
		)
		assert_null(_scene(test_peer), "the game scene is gone")
	assert_engine_error_count(0)

func test_game_scene_can_be_changed_during_the_game() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var everyone: Array[LobbyTestPeer] = [host, client]
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(client) == 2, "everyone is spawned")
	var first_scene_id: int = _scene(client).get_instance_id()
	await _keep_pawns_moving(everyone, 10)
	assert_true(host.service.change_game_scene(GAME_SCENE), "the host can change the scene")
	assert_false(client.service.change_game_scene(GAME_SCENE), "a client cannot")
	await _keep_pawns_moving(everyone, 30)
	await _until(
		func() -> bool:
			return (
				_scene(client) != null and _scene(client).get_instance_id() != first_scene_id
				and _pawn_count(client) == 2
			),
		"everyone is spawned in the new scene"
	)
	assert_eq(client.service.state, LobbyTypes.State.IN_GAME)
	assert_engine_error_count(0)

func test_kick_during_the_game_stops_replication_cleanly() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	var everyone: Array[LobbyTestPeer] = [host, client, other]
	host.service.start_game()
	await _until(func() -> bool: return _pawn_count(other) == 3, "everyone is spawned")
	await _keep_pawns_moving(everyone, 10)
	host.service.kick(host.service.get_member(client.service.local_member.peer_id))
	await _keep_pawns_moving(everyone, 30)
	await _until(func() -> bool: return _pawn_count(host) == 2, "host removed the pawn")
	await _until(func() -> bool: return _pawn_count(other) == 2, "other client removed the pawn")
	assert_eq(client.service.last_reason, LobbyTypes.Reason.KICKED)
	assert_engine_error_count(0)
