extends Node
var app_id: String = "480"
var user: SteamUser
var lobby: SteamLobby
var network: SteamNetwork

func _init() -> void:
	OS.set_environment("SteamAppId", app_id)
	OS.set_environment("SteamGameId", app_id)

func _ready() -> void:
	Steam.steamInit()
	user = SteamUser.new(Steam.getSteamID(), Steam.getPersonaName())
	lobby = SteamLobby.new(user)
	network = SteamNetwork.new(lobby)
	lobby.network = network
	add_child(lobby)
	add_child(network)

func _process(_delta: float) -> void:
	Steam.run_callbacks()
