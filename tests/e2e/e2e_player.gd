extends Node
## Autopilot of an end-to-end run: plays one role (host, client or late joiner) in the
## real game, through the real autoloads and scenes, and quits with a non-zero exit code
## when something is not as expected. See tests/e2e/run.sh.

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

func _play_host() -> void:
	Lobby.create()
	await _until(Lobby.is_host, "lobby created")
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.members.size() == 2, "client joined")
	await _until(Lobby.are_all_ready, "client ready")
	_check(Lobby.start_game(), "game started")
	await _play_game()
	Lobby.return_to_lobby()
	await _until_scene(Lobby.config.lobby_scene)
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_LOBBY, "everyone is back in the lobby")
	_check(Lobby.can_start_game(), "can start again")
	_check(Lobby.members.size() == EXPECTED_PLAYERS, "everyone came back")
	for member: LobbyMember in Lobby.get_members():
		if member.name == "Late":
			Lobby.kick(member)
	await _until(func() -> bool: return Lobby.members.size() == 2, "late player kicked")
	await get_tree().create_timer(1.0).timeout
	Lobby.leave()
	await _until_scene(Lobby.config.main_menu_scene)

func _play_client() -> void:
	Lobby.join(0)
	await _until(Lobby.is_in_lobby, "joined")
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.is_host(), "not host")
	_check(Lobby.get_member(1).name == "Host", "knows the host by name")
	Lobby.set_ready(true)
	await _play_game()
	await _until_scene(Lobby.config.lobby_scene)
	_check(not Lobby.local_member.is_ready, "ready flag cleared")
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.NONE, "lobby closed")
	_check(Lobby.last_reason == LobbyTypes.Reason.HOST_LEFT, "told that the host left")
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

## In game: everyone sees every character, named, where its owner put it.
func _play_game() -> void:
	await _until(func() -> bool: return Lobby.state == LobbyTypes.State.IN_GAME, "in game")
	await _until(func() -> bool: return _players().size() == EXPECTED_PLAYERS, "every character is spawned")
	var own_player: Player = _player_of(Lobby.local_member.name)
	_check(own_player != null and own_player.is_multiplayer_authority(), "controls its own character")
	own_player.position.x = TARGET_X[_role]
	for player_name: String in ["Host", "Client", "Late"]:
		var target_x: float = TARGET_X[player_name.to_lower()]
		await _until(
			func() -> bool:
				var player: Player = _player_of(player_name)
				return player != null and absf(player.position.x - target_x) < 0.5,
			"sees %s at its place" % player_name
		)
	await get_tree().create_timer(1.0).timeout
	# Falling off the map: the host puts the character back on a spawn point.
	own_player.position.y = -50.0
	await _until(func() -> bool: return own_player.position.y > -5.0, "respawned after falling")
	await get_tree().create_timer(0.5).timeout

func _players() -> Array[Node]:
	var container: Node = get_tree().current_scene.get_node_or_null("Players") if get_tree().current_scene else null
	return container.get_children() if container != null else []

func _player_of(member_name: String) -> Player:
	for member: LobbyMember in Lobby.get_members():
		if member.name == member_name:
			for player: Node in _players():
				if player.name == str(member.peer_id):
					return player as Player
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
			_fail("timeout waiting for: %s" % what)
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_log("ok: %s" % what)

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
	print("[e2e %s] %s" % [_role, text])
