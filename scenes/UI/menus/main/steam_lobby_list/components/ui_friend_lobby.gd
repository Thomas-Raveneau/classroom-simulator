class_name UiFriendLobby
extends HBoxContainer

@onready var name_label: Label = $NameLabel

var friend_lobby: SteamFriendLobby
var current_scene: Node

func _ready() -> void:
	if !friend_lobby || !current_scene:
		push_error("UiFriendLobby not set up")
		queue_free()
		return
	name_label.text = friend_lobby.name

func setup(_friend_lobby: SteamFriendLobby, _current_scene: Node) -> void:
	friend_lobby = _friend_lobby
	current_scene = _current_scene

func _on_join_button_pressed() -> void:
	NetworkManager.steam.lobby.join(friend_lobby.id)
	SceneManager.load_scene(
		current_scene,
		NetworkManager.lobby.on_loaded,
		load("res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn")
	)
