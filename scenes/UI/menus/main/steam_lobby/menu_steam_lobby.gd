extends Control

const friend_invite_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby/components/ui_friend_invite.tscn"
)

@onready var friends_container: VBoxContainer = $FriendsContainer
@onready var players_container: VBoxContainer = $PlayersContainer

func _ready() -> void:
	SteamManager.lobby.on_members_refreshed.connect(refresh_members)
	SteamManager.user.on_friends_refreshed.connect(refresh_friends)
	refresh_friends()
	refresh_members()

func refresh_members() -> void:
	for child: Label in players_container.get_children():
		child.queue_free()
	for member: SteamUser in SteamManager.lobby.members:
		var player_label: Label = Label.new()
		player_label.text = member.name
		players_container.add_child(player_label)

func refresh_friends() -> void:
	for child: Node in friends_container.get_children():
		child.queue_free()
	for friend: SteamUser in SteamManager.user.friends:
		var friend_invite_instance = friend_invite_component.instantiate()
		friend_invite_instance.friend = friend
		friends_container.add_child(friend_invite_instance)

func _on_back_button_pressed() -> void:
	SteamManager.lobby.leave()
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")
