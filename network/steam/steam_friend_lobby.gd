class_name SteamFriendLobby

var id: int = 0
var name: String
	
func _init(_id: int = 0, _name: String = "") -> void:
	id = _id
	name = _name

func _to_string() -> String:
	return str({"id" = id, "name" = name})
