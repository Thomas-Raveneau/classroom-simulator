extends Control

func _on_create_lobby_button_pressed() -> void:
	NetworkManager.steam.lobby.create()
	SceneManager.load_scene(
		self,
		NetworkManager.steam.lobby.on_created,
		load("res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn")
	)

func _on_join_lobby_button_pressed() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/UI/menus/main/steam_lobby_list/menu_steam_lobby_list.tscn"
	)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
