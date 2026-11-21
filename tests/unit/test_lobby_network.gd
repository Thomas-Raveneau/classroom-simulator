extends GutTest
## Several players in the same process, each with its own lobby service, talking over
## a real ENet connection: what is validated here holds for every backend, since
## members, data and scene loading are synchronized by RPC.

const GAME_SCENE: String = "res://game.tscn"
const LOBBY_SCENE: String = "res://lobby.tscn"
const WAIT: float = 3.0

var _config: LobbyConfig
var _port: int
var _peers: Array[LobbyTestPeer]

func before_each() -> void:
	_config = _make_config()
	_port = LobbyTestPeer.pick_port()
	_peers = []

func after_each() -> void:
	for test_peer: LobbyTestPeer in _peers:
		test_peer.shutdown()
	_peers.clear()

func _make_config() -> LobbyConfig:
	var config: LobbyConfig = LobbyConfig.new()
	config.join_timeout = 2.0
	config.load_timeout = 5.0
	config.dismiss_grace = 0.2
	config.game_scene = GAME_SCENE
	config.lobby_scene = LOBBY_SCENE
	return config

func _add_peer(config: LobbyConfig = _config) -> LobbyTestPeer:
	var test_peer: LobbyTestPeer = LobbyTestPeer.create(self, config, _port)
	_peers.append(test_peer)
	watch_signals(test_peer.service)
	return test_peer

func _add_host() -> LobbyTestPeer:
	var host: LobbyTestPeer = _add_peer()
	host.service.create()
	await wait_for_signal(host.service.created, LobbyTestPeer.patience(WAIT))
	return host

## Adds a player and waits until its attempt to join ends, successfully or not.
func _add_client(config: LobbyConfig = _config) -> LobbyTestPeer:
	var client: LobbyTestPeer = _add_peer(config)
	client.service.join(0)
	await wait_until(
		func() -> bool: return client.service.state != LobbyTypes.State.JOINING, LobbyTestPeer.patience(WAIT)
	)
	return client

func _until(condition: Callable, text: String) -> void:
	await wait_until(condition, LobbyTestPeer.patience(WAIT))
	assert_true(condition.call(), text)

func _state_is(test_peer: LobbyTestPeer, state: LobbyTypes.State) -> Callable:
	return func() -> bool: return test_peer.service.state == state

func _start_game(host: LobbyTestPeer, others: Array[LobbyTestPeer]) -> void:
	host.service.start_game()
	for test_peer: LobbyTestPeer in others:
		await _until(_state_is(test_peer, LobbyTypes.State.IN_GAME), "player is in game")
	await _until(_state_is(host, LobbyTypes.State.IN_GAME), "host is in game")

# --- Joining -----------------------------------------------------------------------------

func test_client_is_admitted_and_everyone_knows_everyone() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	assert_eq(client.service.state, LobbyTypes.State.IN_LOBBY)
	assert_signal_emitted(client.service, "joined")
	assert_false(client.service.is_host())
	assert_eq(host.service.members.size(), 2)
	assert_eq(client.service.members.size(), 2)
	var client_peer_id: int = client.service.local_member.peer_id
	assert_ne(client_peer_id, 1)
	assert_eq(
		host.service.get_member(client_peer_id).name, client.backend.get_local_identity()["name"],
		"the host knows the name of the client"
	)
	assert_eq(
		client.service.get_member(1).name, host.backend.get_local_identity()["name"],
		"the client knows the name of the host"
	)
	assert_true(client.service.get_member(1).is_host)
	assert_eq(client.service.lobby_name, host.service.lobby_name)
	assert_signal_emit_count(client.service, "member_joined", 2)

func test_members_learn_about_a_newcomer() -> void:
	var host: LobbyTestPeer = await _add_host()
	var first: LobbyTestPeer = await _add_client()
	var second: LobbyTestPeer = await _add_client()
	await _until(func() -> bool: return first.service.members.size() == 3, "first client sees 3 members")
	assert_eq(host.service.members.size(), 3)
	assert_eq(second.service.members.size(), 3)
	assert_eq(
		first.service.get_member(second.service.local_member.peer_id).name,
		second.service.local_member.name
	)

func test_joining_a_missing_lobby_fails() -> void:
	var client: LobbyTestPeer = await _add_client()
	assert_eq(client.service.state, LobbyTypes.State.NONE)
	assert_signal_emitted(client.service, "join_failed")

func test_full_lobby_refuses_newcomers() -> void:
	_config.max_players = 2
	await _add_host()
	await _add_client()
	var late: LobbyTestPeer = await _add_client()
	assert_eq(late.service.state, LobbyTypes.State.NONE)
	assert_signal_emitted_with_parameters(late.service, "join_failed", [LobbyTypes.Reason.LOBBY_FULL])

func test_other_game_version_is_refused() -> void:
	var host: LobbyTestPeer = await _add_host()
	var other_config: LobbyConfig = _make_config()
	other_config.protocol_version = _config.protocol_version + 1
	var client: LobbyTestPeer = await _add_client(other_config)
	assert_signal_emitted_with_parameters(
		client.service, "join_failed", [LobbyTypes.Reason.VERSION_MISMATCH]
	)
	assert_eq(host.service.members.size(), 1)

# --- Leaving -----------------------------------------------------------------------------

func test_client_leaving_is_seen_by_the_others() -> void:
	var host: LobbyTestPeer = await _add_host()
	var first: LobbyTestPeer = await _add_client()
	var second: LobbyTestPeer = await _add_client()
	first.service.leave()
	await _until(func() -> bool: return host.service.members.size() == 2, "host sees the departure")
	await _until(func() -> bool: return second.service.members.size() == 2, "other client sees the departure")
	assert_signal_emitted(host.service, "member_left")
	assert_signal_emitted(second.service, "member_left")

func test_host_leaving_closes_the_lobby_for_clients() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.leave()
	await _until(_state_is(client, LobbyTypes.State.NONE), "client is out")
	assert_signal_emitted_with_parameters(client.service, "left", [LobbyTypes.Reason.HOST_LEFT])
	assert_eq(client.service.last_reason, LobbyTypes.Reason.HOST_LEFT)
	assert_eq(client.service.members.size(), 0)
	assert_false(client.service.can_rejoin(), "nothing to come back to")

func test_kicked_player_is_told_and_cannot_come_back() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	host.service.kick(host.service.get_member(client.service.local_member.peer_id))
	await _until(_state_is(client, LobbyTypes.State.NONE), "kicked client is out")
	await _until(func() -> bool: return host.service.members.size() == 2, "host forgot the kicked client")
	assert_signal_emitted_with_parameters(client.service, "left", [LobbyTypes.Reason.KICKED])
	await _until(func() -> bool: return other.service.members.size() == 2, "other client sees the kick")
	client.service.join(0)
	await _until(_state_is(client, LobbyTypes.State.NONE), "kicked client is refused")
	assert_signal_emitted_with_parameters(client.service, "join_failed", [LobbyTypes.Reason.BANNED])
	assert_eq(host.service.members.size(), 2)

func test_only_the_host_can_kick() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	client.service.kick(client.service.get_member(1))
	await wait_seconds(0.3)
	assert_eq(host.service.state, LobbyTypes.State.IN_LOBBY)
	assert_eq(client.service.members.size(), 2)

func test_silent_peer_is_disconnected_by_the_host() -> void:
	# A peer that connects but never introduces itself is not a member and is cut off.
	_config.join_timeout = 0.4
	var host: LobbyTestPeer = await _add_host()
	var raw_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	raw_peer.create_client(ENetLobbyBackend.ADDRESS, _port)
	var raw_api: SceneMultiplayer = SceneMultiplayer.new()
	var raw_branch: Node = add_child_autofree(Node.new())
	get_tree().set_multiplayer(raw_api, raw_branch.get_path())
	raw_api.multiplayer_peer = raw_peer
	await wait_until(
		func() -> bool: return raw_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		LobbyTestPeer.patience(WAIT)
	)
	assert_eq(host.service.members.size(), 1, "connected but not a member")
	await _until(
		func() -> bool: return raw_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED,
		"silent peer is disconnected"
	)
	get_tree().set_multiplayer(null, raw_branch.get_path())

# --- Data --------------------------------------------------------------------------------

func test_member_data_reaches_everyone() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	var client_peer_id: int = client.service.local_member.peer_id
	client.service.set_member_data("team", 2)
	for test_peer: LobbyTestPeer in [host, client, other]:
		await _until(
			func() -> bool: return test_peer.service.get_member(client_peer_id).data.get("team") == 2,
			"team is known"
		)
	host.service.set_member_data("team", 1)
	await _until(
		func() -> bool: return client.service.get_member(1).data.get("team") == 1,
		"host data reaches the client"
	)
	assert_signal_emitted(other.service, "member_updated")

func test_newcomer_receives_existing_data() -> void:
	var host: LobbyTestPeer = await _add_host()
	host.service.set_member_data("team", 1)
	host.service.set_lobby_data("map", "forest")
	var client: LobbyTestPeer = await _add_client()
	assert_eq(client.service.get_member(1).data.get("team"), 1)
	assert_eq(client.service.get_lobby_data("map"), "forest")

func test_host_can_write_the_data_of_a_client() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.set_member_data("team", 4, host.service.get_member(client.service.local_member.peer_id))
	await _until(
		func() -> bool: return client.service.local_member.data.get("team") == 4,
		"client receives the data set by the host"
	)

func test_client_cannot_write_the_data_of_someone_else() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	client.service.set_member_data("team", 9, client.service.get_member(1))
	client.service.set_lobby_data("map", "hacked")
	await wait_seconds(0.3)
	assert_false(host.service.local_member.data.has("team"))
	assert_null(host.service.get_lobby_data("map"))
	assert_null(client.service.get_lobby_data("map"))

func test_lobby_data_reaches_clients() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.set_lobby_data("map", "desert")
	await _until(func() -> bool: return client.service.get_lobby_data("map") == "desert", "map is known")
	assert_signal_emitted_with_parameters(client.service, "lobby_data_changed", ["map"])

func test_ready_flags_gate_the_start_when_required() -> void:
	_config.require_all_ready = true
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	assert_false(host.service.can_start_game())
	assert_false(host.service.start_game())
	client.service.set_ready(true)
	await _until(host.service.can_start_game, "host can start once the client is ready")
	client.service.set_ready(false)
	await _until(func() -> bool: return not host.service.can_start_game(), "start is blocked again")

# --- Game --------------------------------------------------------------------------------

func test_game_starts_once_everyone_has_loaded() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.loader.manual = true
	client.loader.manual = true
	host.service.start_game()
	await _until(_state_is(client, LobbyTypes.State.LOADING), "client is loading")
	assert_eq(client.loader.pending_path, GAME_SCENE)
	host.loader.complete()
	await wait_seconds(0.2)
	assert_eq(host.service.state, LobbyTypes.State.LOADING, "the host waits for the client")
	assert_signal_not_emitted(host.service, "member_scene_ready")
	client.loader.complete()
	await _until(_state_is(host, LobbyTypes.State.IN_GAME), "host is in game")
	await _until(_state_is(client, LobbyTypes.State.IN_GAME), "client is in game")
	assert_signal_emit_count(host.service, "member_scene_ready", 2)
	assert_signal_emit_count(client.service, "member_scene_ready", 2)
	assert_signal_emit_count(client.service, "game_started", 1)

func test_only_the_host_can_start() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	assert_false(client.service.start_game())
	await wait_seconds(0.2)
	assert_eq(host.service.state, LobbyTypes.State.IN_LOBBY)

func test_player_leaving_while_loading_does_not_block_the_game() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	client.loader.manual = true
	host.service.start_game()
	await _until(_state_is(client, LobbyTypes.State.LOADING), "client is loading")
	client.service.leave()
	await _until(_state_is(host, LobbyTypes.State.IN_GAME), "host is in game without the client")
	assert_eq(host.service.members.size(), 1)

func test_player_too_slow_to_load_is_removed() -> void:
	_config.load_timeout = 0.5
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	client.loader.manual = true
	host.service.start_game()
	await _until(_state_is(host, LobbyTypes.State.IN_GAME), "host is in game")
	await _until(_state_is(client, LobbyTypes.State.NONE), "slow client is out")
	assert_signal_emitted_with_parameters(client.service, "left", [LobbyTypes.Reason.LOAD_FAILED])

func test_locked_lobby_refuses_players_during_the_game() -> void:
	var host: LobbyTestPeer = await _add_host()
	var others: Array[LobbyTestPeer] = []
	await _start_game(host, others)
	var late: LobbyTestPeer = await _add_client()
	assert_eq(late.service.state, LobbyTypes.State.NONE)
	assert_signal_emitted_with_parameters(
		late.service, "join_failed", [LobbyTypes.Reason.GAME_IN_PROGRESS]
	)
	assert_eq(host.service.members.size(), 1)

func test_player_joining_in_progress_loads_the_game() -> void:
	_config.allow_join_in_progress = true
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var others: Array[LobbyTestPeer] = [client]
	await _start_game(host, others)
	var late: LobbyTestPeer = _add_peer()
	late.loader.manual = true
	late.service.join(0)
	await _until(_state_is(late, LobbyTypes.State.LOADING), "late player is loading the game")
	assert_eq(late.loader.pending_path, GAME_SCENE)
	var late_peer_id: int = late.service.local_member.peer_id
	assert_false(host.service.is_peer_scene_ready(late_peer_id))
	assert_signal_emit_count(host.service, "member_scene_ready", 2)
	late.loader.complete()
	await _until(_state_is(late, LobbyTypes.State.IN_GAME), "late player is in game")
	await _until(
		func() -> bool: return client.service.is_peer_scene_ready(late_peer_id),
		"the other client knows the late player is ready"
	)
	assert_true(host.service.is_peer_scene_ready(late_peer_id))
	assert_signal_emit_count(host.service, "member_scene_ready", 3)
	assert_signal_emit_count(client.service, "member_scene_ready", 3)
	assert_signal_emit_count(late.service, "member_scene_ready", 3)

func test_return_to_lobby_brings_everyone_back() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	client.service.set_ready(true)
	var others: Array[LobbyTestPeer] = [client]
	await _start_game(host, others)
	host.service.return_to_lobby()
	await _until(_state_is(host, LobbyTypes.State.IN_LOBBY), "host is back in the lobby")
	await _until(_state_is(client, LobbyTypes.State.IN_LOBBY), "client is back in the lobby")
	assert_eq(client.loader.current_path, LOBBY_SCENE)
	assert_false(client.service.local_member.is_ready, "ready flags are cleared")
	var late: LobbyTestPeer = await _add_client()
	assert_eq(late.service.state, LobbyTypes.State.IN_LOBBY, "the lobby is open again")
	assert_eq(late.loader.requested_paths.size(), 0, "no game scene is pushed to a lobby newcomer")
	var again: Array[LobbyTestPeer] = [client, late]
	await _start_game(host, again)

func test_kicked_player_ignoring_the_notice_is_disconnected() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	# A modified client could ignore the request to leave.
	client.service._member_sync.dismissed.disconnect(client.service._on_dismissed)
	host.service.kick(host.service.get_member(client.service.local_member.peer_id))
	client.service.set_member_data("team", 1)
	await _until(_state_is(client, LobbyTypes.State.NONE), "stubborn client is disconnected")
	assert_eq(host.service.members.size(), 1)

func test_latency_of_each_member_is_published() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	var other: LobbyTestPeer = await _add_client()
	var client_peer_id: int = client.service.local_member.peer_id
	assert_eq(client.service.local_member.ping, -1, "unknown before the first measure")
	await _until(
		func() -> bool: return other.service.get_member(client_peer_id).ping >= 0,
		"another client knows the latency of the client"
	)
	if LobbyTestPeer.conditions_from_environment() == null:
		assert_lt(host.service.get_member(client_peer_id).ping, 200, "a local connection is fast")
	assert_eq(other.service.get_member(1).ping, 0, "the host has none")

func test_simulated_bad_connection_shows_in_the_latency() -> void:
	var host: LobbyTestPeer = await _add_host()
	var conditions: NetworkConditions = NetworkConditions.new()
	conditions.latency_ms = 200
	var slow: LobbyTestPeer = LobbyTestPeer.create(self, _config, _port, conditions)
	_peers.append(slow)
	slow.service.join(0)
	await _until(_state_is(slow, LobbyTypes.State.IN_LOBBY), "joined through the simulated connection")
	var slow_peer_id: int = slow.service.local_member.peer_id
	await _until(
		func() -> bool: return host.service.get_member(slow_peer_id).ping >= 150,
		"the host measures the latency that was added"
	)

func test_member_cannot_write_a_host_only_key() -> void:
	var host: LobbyTestPeer = await _add_host()
	var client: LobbyTestPeer = await _add_client()
	host.service.host_only_member_keys.append("team")
	client.service.set_member_data("team", 3)
	client.service.set_member_data(LobbyMember.PING_KEY, -500)
	client.service.set_member_data("color", "red")
	var client_peer_id: int = client.service.local_member.peer_id
	await _until(
		func() -> bool: return host.service.get_member(client_peer_id).data.get("color") == "red",
		"an ordinary key is accepted"
	)
	assert_false(host.service.get_member(client_peer_id).data.has("team"))
	assert_ne(host.service.get_member(client_peer_id).ping, -500)
	host.service.set_member_data("team", 2, host.service.get_member(client_peer_id))
	await _until(func() -> bool: return client.service.local_member.data.get("team") == 2, "the host can")
