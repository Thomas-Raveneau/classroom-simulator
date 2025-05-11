extends Control

@onready var lobbies_container: VBoxContainer = $LobbiesContainer

const friend_lobby_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby_list/components/ui_friend_lobby.tscn"
)

func _ready() -> void:
	NetworkManager.local_user.steam.on_friends_refreshed.connect(refresh_friends_lobbies)
	NetworkManager.local_user.steam.on_friend_lobby_update.connect(refresh_friends_lobbies)
	refresh_friends_lobbies()

func refresh_friends_lobbies() -> void:
	for child: Node in lobbies_container.get_children():
		child.queue_free()
	var friends_lobbies: Array[SteamFriendLobby] = NetworkManager.local_user.steam.get_friends_lobbies()
	for friend_lobby in friends_lobbies:
		if friend_lobby.id == 0 || !friend_lobby.name:
			continue
		var friend_lobby_instance: UiFriendLobby = friend_lobby_component.instantiate()
		friend_lobby_instance.setup(friend_lobby)
		lobbies_container.add_child(friend_lobby_instance)

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")
