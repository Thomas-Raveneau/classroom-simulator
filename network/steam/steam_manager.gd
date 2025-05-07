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
	lobby = SteamLobby.new()
	network = SteamNetwork.new()
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func is_enabled():
	return OS.has_feature("steam") or OS.is_debug_build()

func get_local_user() -> SteamUser:
	var steam_user := SteamUser.new(Steam.getSteamID(), Steam.getPersonaName())
	steam_user.refresh_friends()
	return steam_user

func _exit_tree():
	lobby.leave()
