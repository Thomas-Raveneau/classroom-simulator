extends Control

const friend_invite_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby/components/ui_friend_invite.tscn"
)
const lobby_player_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby/components/ui_lobby_player.tscn"
)

@onready var friends_container: VBoxContainer = $FriendsContainer
@onready var players_container: VBoxContainer = $PlayersContainer
@onready var private_button: Button = $PrivateButton
@onready var start_button: Button = $StartButton

var loaded: bool = false

func _ready() -> void:
	if !NetworkManager.local_user.is_host:
		private_button.hide()
		start_button.hide()
	NetworkManager.lobby.player_connected.connect(_on_player_connected)
	NetworkManager.lobby.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.local_user.steam.on_friends_refreshed.connect(refresh_friends)
	refresh_friends()
	refresh_players()
	loaded = true

func _enter_tree() -> void:
	if !loaded:
		return
	if !NetworkManager.local_user.is_host:
		private_button.hide()
		start_button.hide()
	else:
		private_button.show()
		start_button.show()


func _on_player_connected(player: NetworkUser) -> void:
	print("UI PLAYER CONNECTED")
	var lobby_player_instance = lobby_player_component.instantiate()
	lobby_player_instance.player = player
	players_container.add_child(lobby_player_instance)
	refresh_friends()

func _on_player_disconnected(player: NetworkUser) -> void:
	for child in players_container.get_children():
		if child.player.peer_id != player.peer_id:
			continue
		child.queue_free()
		break
	refresh_friends()

func refresh_players() -> void:
	for player_id in NetworkManager.lobby.players.keys():
		var player: NetworkUser = NetworkManager.lobby.players[player_id]
		var lobby_player_instance = lobby_player_component.instantiate()
		lobby_player_instance.player = player
		players_container.add_child(lobby_player_instance)


func refresh_friends() -> void:
	for child: Node in friends_container.get_children():
		child.queue_free()
	for steam_friend: SteamUser in NetworkManager.local_user.steam.friends:
		if NetworkManager.lobby.has_steam_user(steam_friend.id):
			continue
		var friend_invite_instance = friend_invite_component.instantiate()
		friend_invite_instance.friend = steam_friend
		friends_container.add_child(friend_invite_instance)

func _on_back_button_pressed() -> void:
	NetworkManager.steam.lobby.leave()
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")

func _on_private_button_toggled(private: bool) -> void:
	NetworkManager.steam.lobby.set_private(private)
	private_button.text = "Private" if private else "Friends only"

func _on_start_button_pressed() -> void:
	NetworkManager.start_game()
