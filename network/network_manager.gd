extends Node

signal players_ready

const SERVER: int = 1

var steam: SteamManager
var lobby: NetworkLobby
var local_user: NetworkPlayer
var peer: SteamMultiplayerPeer

var players_ready_count: int = 0

func _ready() -> void:
	steam = SteamManager.new()
	lobby = NetworkLobby.new()
	peer = SteamMultiplayerPeer.new()
	local_user = NetworkPlayer.new()
	local_user.set_steam(steam.get_local_user())
	add_child(steam)
	add_child(lobby)
	steam.lobby.on_created.connect(_on_lobby_joined)
	steam.lobby.on_joined.connect(_on_lobby_joined)
	steam.lobby.on_left.connect(_on_lobby_left)

func reset_multiplayer_peer() -> void:
	peer.close()
	multiplayer.multiplayer_peer = null
	peer = SteamMultiplayerPeer.new()

func reset_local_player() -> void:
	local_user.is_host = false
	local_user.peer_id = 0

@rpc("authority", "call_local", "reliable")
func load_scene(scene_file: String) -> void:
	SceneManager.load_scene(scene_file)
	SceneManager.changed.connect(
		_on_player_changed_scene.rpc_id.bind(SERVER),
		CONNECT_ONE_SHOT
	)

@rpc("any_peer", "call_local", "reliable")
func _on_player_changed_scene() -> void:
	if !is_multiplayer_authority():
		return
	players_ready_count += 1
	if players_ready_count < lobby.players.size():
		return
	players_ready_count = 0
	players_ready.emit()

func _on_lobby_joined() -> void:
	multiplayer.multiplayer_peer = peer
	local_user.peer_id = peer.get_unique_id()
	lobby.set_player(local_user)

func _on_lobby_left() -> void:
	lobby.players = {}
	reset_local_player()
	reset_multiplayer_peer()
