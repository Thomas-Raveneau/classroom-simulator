class_name UnavailableLobbyBackend
extends LobbyBackend
## The backend used when the one asked for cannot be loaded: it is never available, and
## answers every request with a failure, so the game starts and shows its menus anyway.

func is_available() -> bool:
	return false

func get_backend_name() -> String:
	return "none"

func create(_visibility: LobbyTypes.Visibility) -> void:
	_emit_deferred(lobby_create_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)

func join(_lobby_id: int) -> void:
	_emit_deferred(lobby_join_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)

func leave() -> void:
	pass

func get_peer() -> MultiplayerPeer:
	return null

func get_local_identity() -> Dictionary:
	return { "user_id": 0, "name": "" }

func resolve_identity(_peer_id: int, _claim: Dictionary) -> Dictionary:
	return {}
