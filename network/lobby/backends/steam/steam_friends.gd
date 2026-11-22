extends Node
## The Steam friends of the local user who are online.
##
## A single object listens to Steam: the list is rebuilt lazily, and a burst of status
## changes (frequent on Steam) is reported once.

signal changed

## Quiet time after the last change before `changed` is emitted, in seconds.
const NOTIFY_DELAY: float = 0.5

var _app_id: int = 0
var _friends: Array[LobbyUser] = []
var _is_outdated: bool = true
var _notify_timer: Timer

func setup(app_id: int) -> void:
	_app_id = app_id
	_notify_timer = Timer.new()
	_notify_timer.one_shot = true
	_notify_timer.wait_time = NOTIFY_DELAY
	_notify_timer.timeout.connect(changed.emit)
	add_child(_notify_timer)
	Steam.persona_state_change.connect(_on_persona_state_change)

## Online friends sorted by name. `lobby_id` is set for those sitting in a lobby of this game.
func get_friends() -> Array[LobbyUser]:
	if _is_outdated:
		_rebuild()
	return _friends

## Lobbies of this game where at least one friend sits.
func get_lobby_ids() -> Array[int]:
	var lobby_ids: Array[int] = []
	for friend: LobbyUser in get_friends():
		if friend.lobby_id != 0 and not lobby_ids.has(friend.lobby_id):
			lobby_ids.append(friend.lobby_id)
	return lobby_ids

func _rebuild() -> void:
	_is_outdated = false
	_friends.clear()
	for entry: Dictionary in Steam.getUserSteamFriends():
		var steam_id: int = entry.get("id", 0)
		if steam_id == 0 or entry.get("status", Steam.PERSONA_STATE_OFFLINE) == Steam.PERSONA_STATE_OFFLINE:
			continue
		if Steam.getFriendRelationship(steam_id) != Steam.FRIEND_RELATION_FRIEND:
			continue
		var game: Dictionary = Steam.getFriendGamePlayed(steam_id)
		var lobby_id: int = game.get("lobby", 0) if game.get("id", 0) == _app_id else 0
		_friends.append(LobbyUser.new(steam_id, str(entry.get("name", "")), lobby_id))
	_friends.sort_custom(func(a: LobbyUser, b: LobbyUser) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)

func _on_persona_state_change(_steam_id: int, _flags: int) -> void:
	_is_outdated = true
	_notify_timer.start()
