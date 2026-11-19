class_name FakeLobbyBackend
extends LobbyBackend
## Backend under the control of the test: answers asynchronously like a real one,
## with the outcome the test asked for. It has no transport: a joined lobby never connects.

var available: bool = true
var create_result: LobbyTypes.Reason = LobbyTypes.Reason.NONE
var join_result: LobbyTypes.Reason = LobbyTypes.Reason.NONE
## When false, create() and join() never answer.
var answers: bool = true
var local_identity: Dictionary = { "user_id": 42, "name": "Tester" }

var joinable: bool = true
var published_data: Dictionary[String, String] = {}
var published_visibility: LobbyTypes.Visibility = LobbyTypes.Visibility.PRIVATE
var leave_count: int = 0
var invited_user_ids: Array[int] = []

var _peer: MultiplayerPeer

func is_available() -> bool:
	return available

func get_backend_name() -> String:
	return "fake"

func create(visibility: LobbyTypes.Visibility) -> void:
	published_visibility = visibility
	if not answers:
		return
	if create_result != LobbyTypes.Reason.NONE:
		_emit_deferred(lobby_create_failed, create_result)
		return
	_peer = OfflineMultiplayerPeer.new()
	_emit_deferred(lobby_created, 1001)

func join(lobby_id: int) -> void:
	if not answers:
		return
	if join_result != LobbyTypes.Reason.NONE:
		_emit_deferred(lobby_join_failed, join_result)
		return
	_peer = OfflineMultiplayerPeer.new()
	_emit_deferred(lobby_joined, lobby_id)

func leave() -> void:
	leave_count += 1
	_peer = null

func get_peer() -> MultiplayerPeer:
	return _peer

func get_local_identity() -> Dictionary:
	return local_identity

func set_joinable(new_joinable: bool) -> void:
	joinable = new_joinable

func set_visibility(visibility: LobbyTypes.Visibility) -> void:
	published_visibility = visibility

func set_lobby_data(key: String, value: String) -> void:
	published_data[key] = value

func invite(user_id: int) -> void:
	invited_user_ids.append(user_id)
