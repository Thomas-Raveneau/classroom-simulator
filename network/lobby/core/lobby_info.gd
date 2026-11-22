class_name LobbyInfo
extends RefCounted
## A lobby as shown in a lobby list, before joining it.

var id: int = 0
var name: String = ""
var member_count: int = 0
var max_members: int = 0
var in_game: bool = false
## False when the lobby does not take new players (game started, joining in progress off).
var is_open: bool = true
## True when a friend sits in this lobby.
var has_friend: bool = false

func _init(_id: int = 0, _name: String = "") -> void:
	id = _id
	name = _name

func _to_string() -> String:
	return "LobbyInfo(%d, %s, %d/%d)" % [id, name, member_count, max_members]
