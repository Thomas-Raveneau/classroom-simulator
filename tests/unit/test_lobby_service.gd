extends GutTest
## The lobby service alone, on the host side, with a backend controlled by the test.

const GAME_SCENE: String = "res://game.tscn"
const LOBBY_SCENE: String = "res://lobby.tscn"
const WAIT: float = 2.0

var _config: LobbyConfig
var _backend: FakeLobbyBackend
var _loader: FakeSceneLoader
var _service: LobbyService
## The service lives in its own branch with its own multiplayer API, apart from the
## `Lobby` autoload of the project.
var _branch: Node

func before_each() -> void:
	_config = LobbyConfig.new()
	_config.join_timeout = 0.3
	_config.game_scene = GAME_SCENE
	_config.lobby_scene = LOBBY_SCENE
	_branch = Node.new()
	add_child(_branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _branch.get_path())
	_backend = FakeLobbyBackend.new()
	_loader = FakeSceneLoader.new()
	_branch.add_child(_loader)
	_service = LobbyService.new()
	_service.setup(_config, _backend, _loader)
	_branch.add_child(_service)
	watch_signals(_service)

func after_each() -> void:
	_service.leave()
	for child: Node in _branch.get_children():
		child.free()
	get_tree().set_multiplayer(null, _branch.get_path())
	_branch.queue_free()

func _create_lobby() -> void:
	_service.create()
	await wait_for_signal(_service.created, WAIT)

func test_create_makes_the_local_player_host() -> void:
	_service.create()
	assert_eq(_service.state, LobbyTypes.State.CREATING)
	assert_false(_service.is_host(), "not host before the backend answered")
	await wait_for_signal(_service.created, WAIT)
	assert_eq(_service.state, LobbyTypes.State.IN_LOBBY)
	assert_true(_service.is_host())
	assert_eq(_service.lobby_id, 1001)
	assert_eq(_service.members.size(), 1)
	assert_eq(_service.local_member.name, "Tester")
	assert_eq(_service.local_member.user_id, 42)
	assert_signal_emitted(_service, "entered")
	assert_signal_emit_count(_service, "member_joined", 1)

func test_create_publishes_the_lobby_name() -> void:
	await _create_lobby()
	assert_eq(_service.lobby_name, "Tester's lobby")
	assert_eq(_backend.published_data.get("name"), "Tester's lobby")
	assert_eq(_backend.published_data.get("in_game"), "0")

func test_create_uses_the_requested_visibility() -> void:
	_service.create(LobbyTypes.Visibility.PUBLIC)
	await wait_for_signal(_service.created, WAIT)
	assert_eq(_service.visibility, LobbyTypes.Visibility.PUBLIC)
	assert_eq(_backend.published_visibility, LobbyTypes.Visibility.PUBLIC)

func test_create_failure_is_reported() -> void:
	_backend.create_result = LobbyTypes.Reason.BACKEND_ERROR
	_service.create()
	await wait_for_signal(_service.create_failed, WAIT)
	assert_signal_emitted_with_parameters(_service, "create_failed", [LobbyTypes.Reason.BACKEND_ERROR])
	assert_eq(_service.state, LobbyTypes.State.NONE)
	assert_eq(_service.last_reason, LobbyTypes.Reason.BACKEND_ERROR)
	assert_signal_not_emitted(_service, "created")

func test_unavailable_backend_fails_without_changing_state() -> void:
	_backend.available = false
	_service.create()
	assert_eq(_service.state, LobbyTypes.State.NONE)
	await wait_for_signal(_service.create_failed, WAIT)
	assert_signal_emitted_with_parameters(
		_service, "create_failed", [LobbyTypes.Reason.BACKEND_UNAVAILABLE]
	)

func test_create_times_out_when_the_backend_never_answers() -> void:
	_backend.answers = false
	_service.create()
	await wait_for_signal(_service.create_failed, WAIT)
	assert_signal_emitted_with_parameters(_service, "create_failed", [LobbyTypes.Reason.TIMEOUT])
	assert_eq(_service.state, LobbyTypes.State.NONE)

func test_join_failure_is_reported() -> void:
	_backend.join_result = LobbyTypes.Reason.LOBBY_FULL
	_service.join(5)
	assert_eq(_service.state, LobbyTypes.State.JOINING)
	await wait_for_signal(_service.join_failed, WAIT)
	assert_signal_emitted_with_parameters(_service, "join_failed", [LobbyTypes.Reason.LOBBY_FULL])
	assert_eq(_service.state, LobbyTypes.State.NONE)

func test_join_times_out_when_the_host_never_admits() -> void:
	_service.join(5)
	await wait_for_signal(_service.join_failed, WAIT)
	assert_signal_emitted_with_parameters(_service, "join_failed", [LobbyTypes.Reason.TIMEOUT])
	assert_eq(_service.state, LobbyTypes.State.NONE)
	assert_gt(_backend.leave_count, 0, "the backend lobby is left on failure")

func test_timeout_of_a_finished_attempt_is_ignored() -> void:
	await _create_lobby()
	await wait_seconds(_config.join_timeout + 0.1)
	assert_eq(_service.state, LobbyTypes.State.IN_LOBBY)
	assert_signal_not_emitted(_service, "left")

func test_leave_reports_a_voluntary_departure() -> void:
	await _create_lobby()
	_service.leave()
	assert_signal_emitted_with_parameters(_service, "left", [LobbyTypes.Reason.VOLUNTARY])
	assert_eq(_service.state, LobbyTypes.State.NONE)
	assert_eq(_service.members.size(), 0)
	assert_null(_service.local_member)
	assert_false(_service.is_host())

func test_joining_leaves_the_current_lobby_first() -> void:
	await _create_lobby()
	_service.join(5)
	assert_signal_emitted_with_parameters(_service, "left", [LobbyTypes.Reason.VOLUNTARY])
	assert_eq(_service.state, LobbyTypes.State.JOINING)

func test_external_join_request_starts_joining() -> void:
	_backend.join_requested.emit(77)
	assert_eq(_service.state, LobbyTypes.State.JOINING)

func test_backend_closing_the_lobby_ends_it() -> void:
	await _create_lobby()
	_backend.lobby_closed.emit(LobbyTypes.Reason.HOST_LEFT)
	await wait_for_signal(_service.left, WAIT)
	assert_signal_emitted_with_parameters(_service, "left", [LobbyTypes.Reason.HOST_LEFT])

func test_host_sets_its_member_data() -> void:
	await _create_lobby()
	_service.set_member_data("team", 3)
	assert_eq(_service.local_member.data.get("team"), 3)
	assert_signal_emitted_with_parameters(_service, "member_updated", [_service.local_member, "team"])
	_service.set_member_data("team", null)
	assert_false(_service.local_member.data.has("team"))

func test_member_data_validator_can_refuse() -> void:
	await _create_lobby()
	_service.member_data_validator = func(_member: LobbyMember, key: String, _value: Variant) -> bool:
		return key != "forbidden"
	_service.set_member_data("forbidden", 1)
	_service.set_member_data("allowed", 1)
	assert_false(_service.local_member.data.has("forbidden"))
	assert_true(_service.local_member.data.has("allowed"))

func test_oversized_or_object_member_data_is_refused() -> void:
	await _create_lobby()
	_service.set_member_data("big", "x".repeat(LobbyMemberSync.MAX_VALUE_BYTES + 1))
	_service.set_member_data("object", RefCounted.new())
	_service.set_member_data("", 1)
	assert_eq(_service.local_member.data.size(), 0)

func test_lobby_data_is_set_by_the_host() -> void:
	await _create_lobby()
	_service.set_lobby_data("map", "forest")
	assert_eq(_service.get_lobby_data("map"), "forest")
	assert_eq(_service.get_lobby_data("missing", "default"), "default")
	assert_signal_emitted_with_parameters(_service, "lobby_data_changed", ["map"])

func test_visibility_change_reaches_the_backend() -> void:
	await _create_lobby()
	_service.set_visibility(LobbyTypes.Visibility.PRIVATE)
	assert_eq(_backend.published_visibility, LobbyTypes.Visibility.PRIVATE)
	assert_signal_emitted_with_parameters(
		_service, "visibility_changed", [LobbyTypes.Visibility.PRIVATE]
	)

func test_start_game_loads_the_scene_and_locks_the_lobby() -> void:
	await _create_lobby()
	assert_true(_service.start_game())
	assert_eq(_service.state, LobbyTypes.State.LOADING)
	assert_false(_backend.joinable)
	assert_eq(_backend.published_data.get("in_game"), "1")
	await wait_for_signal(_service.game_started, WAIT)
	assert_eq(_service.state, LobbyTypes.State.IN_GAME)
	assert_eq(_loader.current_path, GAME_SCENE)
	assert_signal_emitted_with_parameters(_service, "member_scene_ready", [_service.local_member])
	assert_true(_service.is_member_scene_ready(_service.local_member))

func test_start_game_keeps_the_lobby_open_when_joining_in_progress_is_allowed() -> void:
	_config.allow_join_in_progress = true
	await _create_lobby()
	_service.start_game()
	assert_true(_backend.joinable)

func test_start_game_accepts_another_scene() -> void:
	await _create_lobby()
	_service.start_game("res://other.tscn")
	await wait_for_signal(_service.game_started, WAIT)
	assert_eq(_loader.current_path, "res://other.tscn")

func test_game_cannot_start_twice_nor_outside_a_lobby() -> void:
	assert_false(_service.start_game(), "not in a lobby")
	await _create_lobby()
	assert_true(_service.start_game())
	assert_false(_service.start_game(), "already loading")

func test_failed_scene_load_closes_the_lobby() -> void:
	_loader.manual = true
	await _create_lobby()
	_service.start_game()
	_loader.fail()
	await wait_for_signal(_service.left, WAIT)
	assert_signal_emitted_with_parameters(_service, "left", [LobbyTypes.Reason.LOAD_FAILED])

func test_return_to_lobby_reopens_it() -> void:
	await _create_lobby()
	_service.set_ready(true)
	_service.start_game()
	await wait_for_signal(_service.game_started, WAIT)
	_service.return_to_lobby()
	assert_eq(_service.state, LobbyTypes.State.LOADING)
	await wait_until(func() -> bool: return _service.state == LobbyTypes.State.IN_LOBBY, WAIT)
	assert_eq(_service.state, LobbyTypes.State.IN_LOBBY)
	assert_eq(_loader.current_path, LOBBY_SCENE)
	assert_true(_backend.joinable)
	assert_eq(_backend.published_data.get("in_game"), "0")
	assert_false(_service.local_member.is_ready, "ready flags are cleared")
	assert_true(_service.can_start_game())

func test_invites_are_kept_until_answered() -> void:
	var sender: LobbyUser = LobbyUser.new(9, "Friend")
	_backend.invite_received.emit(LobbyInvite.new(sender, 500))
	_backend.invite_received.emit(LobbyInvite.new(sender, 500))
	_backend.invite_received.emit(LobbyInvite.new(sender, 501))
	assert_eq(_service.invites.size(), 2, "the same invite is not listed twice")
	assert_eq(_service.invites[0].lobby_id, 501, "most recent first")
	_service.decline_invite(_service.invites[0])
	assert_eq(_service.invites.size(), 1)
	_service.accept_invite(_service.invites[0])
	assert_eq(_service.invites.size(), 0)
	assert_eq(_service.state, LobbyTypes.State.JOINING)

func test_invite_requires_a_lobby() -> void:
	_service.invite(9)
	assert_eq(_backend.invited_user_ids.size(), 0)
	await _create_lobby()
	_service.invite(9)
	assert_eq(_backend.invited_user_ids, [9] as Array[int])

func test_for_node_finds_the_service_of_a_node() -> void:
	assert_eq(LobbyService.for_node(_loader), _service)
	assert_ne(LobbyService.for_node(self), _service, "another multiplayer API, another service")
