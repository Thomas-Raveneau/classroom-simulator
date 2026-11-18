class_name SteamManager
extends Node

var app_id: int = 480
var lobby: SteamLobby
var network: SteamNetwork
var initialized: bool = false

func _init() -> void:
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))
	# Initialize as soon as the manager is created: NetworkManager uses Steam before adding it to the tree
	if is_enabled():
		initialized = Steam.steamInit() && Steam.isSubscribed()

func _ready() -> void:
	if !initialized:
		return
	lobby = SteamLobby.new()
	network = SteamNetwork.new()
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	if initialized:
		Steam.run_callbacks()

func is_enabled() -> bool:
	return OS.has_feature("steam") or OS.is_debug_build()

func get_local_user() -> SteamUser:
	var steam_user: SteamUser = SteamUser.new(Steam.getSteamID(), Steam.getPersonaName())
	steam_user.refresh_friends()
	return steam_user
