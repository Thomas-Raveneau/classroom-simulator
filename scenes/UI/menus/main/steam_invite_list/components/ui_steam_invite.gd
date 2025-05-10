class_name UiSteamInvite
extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var accept_button: Button = $AcceptButton

var user: SteamUser
var lobby_id: int = 0
var current_scene: Node

func _ready() -> void:
	if !user || !user.name || lobby_id == 0 || !current_scene:
		printerr("ui_steam_invite not set up")
		queue_free()
		return
	name_label.text = user.name

func setup(_user: SteamUser, _lobby_id: int, _current_scene: Node) -> void:
	user = _user
	lobby_id = _lobby_id
	current_scene = _current_scene

func _on_accept_button_pressed() -> void:
	NetworkManager.steam.lobby.join(lobby_id)
	SceneManager.load_scene(
		current_scene,
		NetworkManager.lobby.on_loaded,
		load("res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn")
	)
