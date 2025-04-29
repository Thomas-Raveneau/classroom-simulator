extends Node

var steam: SteamManager
var multi: MultiplayerManager
var peer: SteamMultiplayerPeer

func _ready() -> void:
	steam = SteamManager.new()
	multi = MultiplayerManager.new()
	peer = SteamMultiplayerPeer.new()
	add_child(steam)

func reset_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = null
	peer.close()
	peer = SteamMultiplayerPeer.new()

func set_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = peer
