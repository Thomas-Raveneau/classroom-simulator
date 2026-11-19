class_name LobbyInvite
extends RefCounted
## An invitation to a lobby received by the local player.

var from: LobbyUser
var lobby_id: int = 0

func _init(_from: LobbyUser = null, _lobby_id: int = 0) -> void:
	from = _from
	lobby_id = _lobby_id
