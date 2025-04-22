extends Node
var app_id: String = "480"
var is_host: bool = false
var user: SteamUser

func _init() -> void:
	OS.set_environment("SteamAppId", app_id)
	OS.set_environment("SteamGameId", app_id)

func _ready() -> void:
	Steam.steamInit()
	var user_id: int = Steam.getSteamID()
	var username: String = Steam.getPersonaName()
	user = SteamUser.new(user_id, username)
	var steam_lobby: SteamLobby = SteamLobby.new(user)
	add_child(steam_lobby)

func _process(_delta: float) -> void:
	Steam.run_callbacks()
