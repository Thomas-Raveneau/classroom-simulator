extends Control

@onready var lobbies_container: VBoxContainer = $LobbiesContainer

const friend_lobby_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby_list/components/ui_friend_lobby.tscn"
)

func _ready() -> void:
	NetworkManager.steam.user.on_friends_refreshed.connect(refresh_friends_lobbies)
	NetworkManager.steam.user.on_friend_lobby_update.connect(refresh_friends_lobbies)
	NetworkManager.steam.lobby.on_joined.connect(_on_lobby_joined)
	refresh_friends_lobbies()

func refresh_friends_lobbies() -> void:
	for child: Node in lobbies_container.get_children():
		child.queue_free()
	var friends_lobbies: Array[SteamFriendLobby] = NetworkManager.steam.user.get_friends_lobbies()
	for friend_lobby in friends_lobbies:
		if friend_lobby.id == 0 || !friend_lobby.name:
			continue
		var friend_lobby_instance = friend_lobby_component.instantiate()
		friend_lobby_instance.friend_lobby = friend_lobby
		lobbies_container.add_child(friend_lobby_instance)

func _on_lobby_joined():
	get_tree().change_scene_to_file(
		"res://scenes/UI/menus/main/steam_lobby/menu_steam_lobby.tscn"
	)

func _on_back_button_pressed() -> void:
	NetworkManager.steam.lobby.leave()
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")
