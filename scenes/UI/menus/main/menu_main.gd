extends Control

func _ready() -> void:
	SteamManager.lobby.on_created.connect(_on_lobby_created)
	SteamManager.lobby.on_lobby_joined.connect(_on_lobby_joined)


func _on_lobby_created() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn"
	)

func _on_lobby_joined() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn"
	)

func _on_create_lobby_button_pressed() -> void:
	SteamManager.lobby.create()

func _on_join_lobby_button_pressed() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/UI/menus/main/steam_lobby_list/menu_steam_lobby_list.tscn"
	)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
