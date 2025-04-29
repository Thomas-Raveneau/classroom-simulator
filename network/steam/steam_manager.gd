class_name SteamManager
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
	user.refresh_friends()
	lobby = SteamLobby.new()
	network = SteamNetwork.new()
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func is_steam_enabled():
	return OS.has_feature("steam") or OS.is_debug_build()

func start_game() -> void:
	print("TODO HERE")
	return
	#if !user.is_host:
		#return
	#var host_success: bool = NetworkManager.multi.host_game()
	#if !host_success:
		#return
	#var message: Dictionary = {
		#command = "START_GAME",
		#ip = MultiplayerManager.network.ip,
		#port = MultiplayerManager.network.port
	#}
	#network.send_message(message)

func _exit_tree():
	lobby.leave()
