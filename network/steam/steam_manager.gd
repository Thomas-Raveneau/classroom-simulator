class_name SteamManager
extends Node

var app_id: int = 480
var lobby: SteamLobby
var network: SteamNetwork

func _init() -> void:
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))

func _ready() -> void:
	if !is_enabled():
		return
	var init_success: bool = Steam.steamInit()
	if !init_success || !Steam.isSubscribed():
		get_tree().quit()
	init_local_user()
	lobby = SteamLobby.new()
	network = SteamNetwork.new()
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func is_enabled():
	return OS.has_feature("steam") or OS.is_debug_build()

func init_local_user() -> void:
	var steam_user := SteamUser.new(Steam.getSteamID(), Steam.getPersonaName())
	NetworkManager.local_user.set_steam(steam_user)
	NetworkManager.local_user.steam.refresh_friends()

func _exit_tree():
	lobby.leave()
