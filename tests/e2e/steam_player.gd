extends "res://tests/e2e/e2e_player.gd"
## Autopilot of an end-to-end run over Steam, with two players on two machines, each
## logged in to its own Steam account. One machine plays the host, the other the client:
##
##   godot --path . res://tests/e2e/steam_player.tscn -- --e2e-role=host
##   godot --path . res://tests/e2e/steam_player.tscn -- --e2e-role=client
##
## The host creates a public lobby. The client finds it in the lobby list (or joins
## `--e2e-lobby=<id>` directly, the id being printed by the host), then both play a round:
## positions, animations, respawn, coins, scores, results and back to the lobby.
## The run ends in one of two ways, chosen with `--e2e-ending=` on both machines:
## - `host_left` (default): the host leaves, the client is told so.
## - `kick`: the host kicks the client, who cannot come back.
##
## What cannot be driven from code is left to a human: invitations, the Steam overlay,
## voice, and cutting a real network connection. See "À vérifier sur Steam" in
## network/README.md.

const LOBBY_ARGUMENT: String = "--e2e-lobby="
const ENDING_ARGUMENT: String = "--e2e-ending="
## How long the client looks for the host's lobby: the host may be started after it.
const SEARCH_TIMEOUT: float = 180.0
const SEARCH_INTERVAL: float = 3.0

var _lobby_id_argument: int = 0
var _ending: String = "host_left"
var _has_failed: bool = false

func _ready() -> void:
	expected_players = 2
	# Steam relays add latency, and each step waits for the other machine.
	timeout = 45.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ROLE_ARGUMENT):
			_role = argument.trim_prefix(ROLE_ARGUMENT)
		elif argument.begins_with(LOBBY_ARGUMENT):
			_lobby_id_argument = argument.trim_prefix(LOBBY_ARGUMENT).to_int()
		elif argument.begins_with(ENDING_ARGUMENT):
			_ending = argument.trim_prefix(ENDING_ARGUMENT)
	reparent.call_deferred(get_tree().root)
	Lobby.left.connect(func(reason: LobbyTypes.Reason) -> void: _log("left: %s" % _reason(reason)))
	Lobby.join_failed.connect(func(reason: LobbyTypes.Reason) -> void: _log("join failed: %s" % _reason(reason)))
	Lobby.create_failed.connect(func(reason: LobbyTypes.Reason) -> void: _log("create failed: %s" % _reason(reason)))
	Lobby.state_changed.connect(
		func(state: LobbyTypes.State) -> void: _log("state: %s" % LobbyTypes.State.find_key(state))
	)
	await get_tree().process_frame
	if not _check_steam():
		return
	if _ending not in ["host_left", "kick"]:
		_fail("unknown ending '%s'" % _ending)
		return
	match _role:
		"host": await _play_steam_host()
		"client": await _play_steam_client()
		_: _fail("unknown role '%s'" % _role)
	if _has_failed:
		return
	_log("OK")
	get_tree().quit(0)

## Remembers the failure: a step that fails returns to its caller, which must not end the
## run as a success in the same frame.
func _fail(what: String) -> void:
	_has_failed = true
	await super(what)

func _check_steam() -> bool:
	var backend: LobbyBackend = Lobby.backend
	if backend == null or backend.get_backend_name() != "steam":
		_fail("the lobby does not use the Steam backend (remove --lobby-backend=enet)")
		return false
	if not backend.is_available():
		_fail("Steam is not available: is the Steam client running and logged in?")
		return false
	_log("Steam user: %s (%d)" % [Steam.getPersonaName(), Steam.getSteamID()])
	return true

# --- Roles -------------------------------------------------------------------------------

func _play_steam_host() -> void:
	Lobby.create(LobbyTypes.Visibility.PUBLIC)
	await _until(Lobby.is_host, "lobby created")
	_log("LOBBY ID: %d (name: %s)" % [Lobby.lobby_id, Lobby.lobby_name])
	await _until_scene(Lobby.config.lobby_scene)
	var waited: float = timeout
	timeout = SEARCH_TIMEOUT
	await _until(func() -> bool: return Lobby.members.size() == 2, "client joined")
	timeout = waited
	await _check_names_and_ping()
	await _until(Lobby.are_all_ready, "client ready")
	_check(Lobby.start_game(), "game started")
	await _until_scene(Lobby.config.game_scene)
	_round().round_seconds = 600.0
	_round().results_seconds = 2.0
	await _play_steam_game()
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_LOBBY, "everyone is back in the lobby")
	_check(Lobby.members.size() == 2, "the client came back")
	await _everyone_did("back_in_lobby")
	match _ending:
		"host_left":
			await get_tree().create_timer(1.0).timeout
			Lobby.leave()
		"kick":
			Lobby.kick(_other_member())
			await _until(func() -> bool: return Lobby.members.size() == 1, "client kicked")
			# The client tries to come back: stays open long enough to refuse it.
			await get_tree().create_timer(20.0).timeout
			_check(Lobby.members.size() == 1, "the kicked client did not come back")
			Lobby.leave()
	await _until_scene(Lobby.config.main_menu_scene)

func _play_steam_client() -> void:
	var lobby_id: int = _lobby_id_argument
	if lobby_id == 0:
		lobby_id = await _find_host_lobby()
		if lobby_id == 0:
			return
	Lobby.join(lobby_id)
	await _until(Lobby.is_in_lobby, "joined lobby %d" % lobby_id)
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.is_host(), "not host")
	await _check_names_and_ping()
	Lobby.set_ready(true)
	await _play_steam_game()
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.local_member.is_ready, "ready flag cleared")
	await _everyone_did("back_in_lobby")
	match _ending:
		"host_left":
			await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "lobby closed")
			_check(Lobby.last_reason == LobbyTypes.Reason.HOST_LEFT, "told that the host left")
			_check(not Lobby.can_rejoin(), "nothing to rejoin")
			await _until_scene(Lobby.config.main_menu_scene)
		"kick":
			await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "removed from the lobby")
			_check(Lobby.last_reason == LobbyTypes.Reason.KICKED, "told about the kick")
			await _until_scene(Lobby.config.main_menu_scene)
			Lobby.join(lobby_id)
			await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "refused when coming back")
			_check(Lobby.last_reason == LobbyTypes.Reason.BANNED, "told that it was kicked earlier")

## Waits for a lobby of this game in the list: the host's, the only one expected.
func _find_host_lobby() -> int:
	var found: Array[int] = []
	var on_list: Callable = func(lobbies: Array[LobbyInfo]) -> void:
		for info: LobbyInfo in lobbies:
			_log("listed: %s" % info)
			if info.member_count == 1 and not info.in_game and info.is_open and found.is_empty():
				found.append(info.id)
	Lobby.lobby_list_received.connect(on_list)
	var elapsed: float = 0.0
	while found.is_empty() and elapsed < SEARCH_TIMEOUT:
		Lobby.request_lobby_list()
		await get_tree().create_timer(SEARCH_INTERVAL).timeout
		elapsed += SEARCH_INTERVAL
	Lobby.lobby_list_received.disconnect(on_list)
	if found.is_empty():
		_fail("no lobby found in the list after %ds: start the host, or pass --e2e-lobby=<id>" % SEARCH_TIMEOUT)
		return 0
	_log("ok: found lobby %d in the list (%.0fs)" % [found[0], elapsed])
	return found[0]

# --- Steps -------------------------------------------------------------------------------

## Both players carry their Steam name, and the host measures the latency of the client.
func _check_names_and_ping() -> void:
	_check(Lobby.local_member.name == Steam.getPersonaName(), "named after its Steam account")
	await _until(func() -> bool: return _other_member() != null and _other_member().name != "", "knows the other by name")
	_log("the other player is %s (user id %d)" % [_other_member().name, _other_member().user_id])
	_check(_other_member().user_id != Lobby.local_member.user_id, "two different Steam accounts")
	await _until(
		func() -> bool: return _client_member() != null and _client_member().ping > 0,
		"sees the latency of the client"
	)
	_log("latency of the client: %d ms" % _client_member().ping)

func _play_steam_game() -> void:
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_GAME, "in game")
	await _until(func() -> bool: return _players().size() == expected_players, "every character is spawned")
	await _check_steam_positions()
	await _everyone_did("positions")
	await _fall_and_respawn()
	await _collect_a_coin()
	await _everyone_did("coins")
	if _role == "host":
		_match_state().start_phase(MatchState.PHASE_PLAYING, 0.5)
	await _until(func() -> bool: return _match_state().phase == MatchState.PHASE_RESULTS, "results are shown")

## Each one sees the other's character where its owner put it, standing still.
func _check_steam_positions() -> void:
	var own_player: Player = _own_player()
	_check(own_player != null and own_player.is_multiplayer_authority(), "controls its own character")
	own_player.position.x = TARGET_X[_role]
	var other_x: float = TARGET_X["client" if _role == "host" else "host"]
	await _until(
		func() -> bool:
			var player: Player = _player_of(_other_member())
			return player != null and absf(player.position.x - other_x) < 0.5,
		"sees the other character at its place"
	)
	await _until(
		func() -> bool:
			var player: Player = _player_of(_other_member())
			return player != null and _animation_of(player) == &"idle",
		"sees the other character standing still"
	)

# --- Helpers -----------------------------------------------------------------------------

func _other_member() -> LobbyMember:
	for member: LobbyMember in Lobby.get_members():
		if member != Lobby.local_member:
			return member
	return null

func _client_member() -> LobbyMember:
	for member: LobbyMember in Lobby.get_members():
		if not member.is_host:
			return member
	return null
