class_name SteamUser

var id: int = 0
var name: String = ""
var is_host: bool = false

func _init(_id: int, _name: String, _is_host: bool = false) -> void:
	id = _id
	name = _name
	is_host = _is_host
