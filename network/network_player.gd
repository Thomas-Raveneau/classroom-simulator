class_name NetworkPlayer

var steam: SteamUser
var name: String = ""
var peer_id: int = 0
var connected: bool = false

func _init(_steam: SteamUser):
	steam = _steam
	name = steam.name
	peer_id = NetworkManager.peer.get_peer_id_from_steam64(steam.id)

func _to_string() -> String:
	return str({ 
		"peer_id" = peer_id,
		"name" = name,
		"connected" = connected
	})
