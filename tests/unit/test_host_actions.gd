extends LobbyGameTest

## What each player saw applied: [member name or "", arguments].
var _applied: Dictionary[LobbyTestPeer, Array] = {}
var _allow: bool = true

func before_each() -> void:
	super()
	_applied = {}
	_allow = true

func _actions(test_peer: LobbyTestPeer) -> HostActions:
	return scene_of(test_peer).actions

## Registers the same "poke" action on every player, as a game would in `_ready()`.
func _register(cooldown: float = 0.0, relay: bool = false) -> void:
	for test_peer: LobbyTestPeer in peers:
		_applied[test_peer] = []
		_actions(test_peer).register(
			&"poke",
			func(_member: LobbyMember, arguments: Array) -> bool:
				return _allow and arguments.size() == 1 and arguments[0] is int,
			func(member: LobbyMember, arguments: Array) -> void:
				_applied[test_peer].append([member.name if member != null else "", arguments]),
			cooldown, relay
		)

func test_request_of_a_client_is_applied_on_the_host_for_that_client() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	_register()
	_actions(client).request(&"poke", [7])
	await until(func() -> bool: return _applied[host].size() == 1, "the host applied the action")
	assert_eq(_applied[host][0], [client.service.local_member.name, [7]], "for the player who asked")
	await wait_seconds(0.2)
	assert_eq(_applied[client].size(), 0, "not relayed by default")

func test_request_of_the_host_is_validated_too() -> void:
	var host: LobbyTestPeer = await add_host()
	await start_game(host)
	_register()
	watch_signals(_actions(host))
	_actions(host).request(&"poke", ["not an int"])
	assert_eq(_applied[host].size(), 0)
	assert_signal_emitted(_actions(host), "action_refused")
	_actions(host).request(&"poke", [1])
	assert_eq(_applied[host].size(), 1)
	assert_signal_emitted(_actions(host), "action_applied")

func test_refused_and_unknown_actions_change_nothing() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	_register()
	watch_signals(_actions(host))
	_allow = false
	_actions(client).request(&"poke", [1])
	_actions(client).request(&"unknown", [1])
	await wait_for_signal(_actions(host).action_refused, WAIT)
	await wait_seconds(0.2)
	assert_eq(_applied[host].size(), 0)
	assert_signal_emit_count(_actions(host), "action_refused", 1, "an unknown action is ignored silently")

func test_cooldown_limits_how_often_a_player_is_granted() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	await start_game(host)
	_register(0.4)
	_actions(client).request(&"poke", [1])
	_actions(client).request(&"poke", [2])
	_actions(host).request(&"poke", [3])
	await until(func() -> bool: return _applied[host].size() == 2, "one grant per player")
	assert_eq(_applied[host][0][1], [3], "the host is not slowed down by the client")
	assert_eq(_applied[host][1][1], [1])
	await wait_seconds(0.5)
	_actions(client).request(&"poke", [4])
	await until(func() -> bool: return _applied[host].size() == 3, "granted again after the cooldown")

func test_relayed_action_runs_on_every_player() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var other: LobbyTestPeer = await add_client()
	await start_game(host)
	_register(0.0, true)
	_actions(client).request(&"poke", [5])
	for test_peer: LobbyTestPeer in [host, client, other]:
		await until(func() -> bool: return _applied[test_peer].size() == 1, "applied on the player")
		assert_eq(_applied[test_peer][0], [client.service.local_member.name, [5]])
	assert_engine_error_count(0)
