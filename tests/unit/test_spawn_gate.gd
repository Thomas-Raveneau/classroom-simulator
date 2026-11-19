extends GutTest
## Real MultiplayerSpawner / MultiplayerSynchronizer replication between players of the
## same process, to validate that LobbySpawnGate makes joining in progress safe.

const GAME_SCENE: String = "res://game.tscn"
const WAIT: float = 3.0

var _config: LobbyConfig
var _port: int
var _peers: Array[LobbyTestPeer]

func before_each() -> void:
	_config = LobbyConfig.new()
	_config.join_timeout = 2.0
	_config.load_timeout = 5.0
	_config.game_scene = GAME_SCENE
	_config.allow_join_in_progress = true
	_port = LobbyTestPeer.pick_port()
	_peers = []

func after_each() -> void:
	for test_peer: LobbyTestPeer in _peers:
		test_peer.shutdown()
	_peers.clear()

func _add_peer() -> LobbyTestPeer:
	var test_peer: LobbyTestPeer = LobbyTestPeer.create(self, _config, _port)
	test_peer.loader.scene_factory = func(_path: String) -> Node: return TestGameScene.new()
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

func _scene(test_peer: LobbyTestPeer) -> TestGameScene:
	return test_peer.loader.current_scene as TestGameScene

func _pawn_count(test_peer: LobbyTestPeer) -> int:
	return _scene(test_peer).pawns.get_child_count() if _scene(test_peer) != null else 0

func _until(condition: Callable, text: String) -> void:
	await wait_until(condition, WAIT)
	assert_true(condition.call(), text)

func _pawn_value_is(viewer: LobbyTestPeer, owner_peer: LobbyTestPeer, value: int) -> Callable:
	return func() -> bool:
		var pawn: TestPawn = _scene(viewer).get_pawn(owner_peer.service.local_member.peer_id)
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
