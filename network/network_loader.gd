class_name NetworkLoader
extends Node

signal players_ready

var players_ready_count: int = 0

@rpc("authority", "call_local", "reliable")
func load_scene(path: String) -> void:
	SceneManager.load_scene(path)
	SceneManager.changed.connect(
		_on_player_changed_scene.rpc_id.bind(NetworkManager.SERVER),
		CONNECT_ONE_SHOT
	)

@rpc("any_peer", "call_local", "reliable")
func _on_player_changed_scene() -> void:
	if !NetworkManager.multiplayer.is_server():
		return
	players_ready_count += 1
	if players_ready_count < NetworkManager.lobby.players.size():
		return
	players_ready_count = 0
	players_ready.emit()
