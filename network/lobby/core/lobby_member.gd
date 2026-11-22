class_name LobbyMember
extends RefCounted
## A player admitted in the lobby.

const READY_KEY: String = "ready"
const PING_KEY: String = "ping"

## Network peer id (1 for the host).
var peer_id: int = 0
## Identity given by the backend (Steam ID with Steam). Stable across reconnections.
var user_id: int = 0
var name: String = ""
## Free-form data synchronized to every member (character, team, ready flag...).
var data: Dictionary[String, Variant] = {}

var is_host: bool:
	get: return peer_id == MultiplayerPeer.TARGET_PEER_SERVER

var is_ready: bool:
	get: return data.get(READY_KEY, false) == true

## Round trip between the host and this member in milliseconds, -1 when not measured yet.
var ping: int:
	get:
		var value: Variant = data.get(PING_KEY)
		return value if value is int else -1

func _init(_peer_id: int = 0, _user_id: int = 0, _name: String = "") -> void:
	peer_id = _peer_id
	user_id = _user_id
	name = _name

func to_dict() -> Dictionary:
	return { "peer_id": peer_id, "user_id": user_id, "name": name, "data": data }

## Returns null when the dictionary is not a valid member.
static func from_dict(dict: Dictionary) -> LobbyMember:
	var raw_peer_id: Variant = dict.get("peer_id")
	var raw_user_id: Variant = dict.get("user_id")
	var raw_name: Variant = dict.get("name")
	var raw_data: Variant = dict.get("data", {})
	if raw_peer_id is not int or raw_user_id is not int:
		return null
	if raw_name is not String or raw_data is not Dictionary:
		return null
	var member: LobbyMember = LobbyMember.new(raw_peer_id, raw_user_id, raw_name)
	var source: Dictionary = raw_data
	for key: Variant in source:
		if key is String:
			member.data[key] = source[key]
	return member

func _to_string() -> String:
	return "LobbyMember(%d, %s)" % [peer_id, name]
