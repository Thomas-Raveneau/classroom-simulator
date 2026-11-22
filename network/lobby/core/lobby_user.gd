class_name LobbyUser
extends RefCounted
## A user of the backend who is not necessarily in the lobby (friend, invite sender).

var id: int = 0
var name: String = ""
## Id of the lobby this user currently sits in, 0 when none or unknown.
var lobby_id: int = 0

func _init(_id: int = 0, _name: String = "", _lobby_id: int = 0) -> void:
	id = _id
	name = _name
	lobby_id = _lobby_id

func _to_string() -> String:
	return "LobbyUser(%d, %s)" % [id, name]
