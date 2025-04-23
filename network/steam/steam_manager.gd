extends Node

var app_id: int = 480
var user: SteamUser
var lobby: SteamLobby
var network: SteamNetwork

func _init() -> void:
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))

func _ready() -> void:
	if !is_steam_enabled():
		return
	var init_success: bool = Steam.steamInit()
	if !init_success || !Steam.isSubscribed():
		get_tree().quit()
	user = SteamUser.new(Steam.getSteamID(), Steam.getPersonaName())
	lobby = SteamLobby.new(user)
	network = SteamNetwork.new(lobby)
	lobby.network = network
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func is_steam_enabled():
	return OS.has_feature("steam") or OS.is_debug_build()
