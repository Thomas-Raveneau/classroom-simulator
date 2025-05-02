extends Control

const friend_invite_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby/components/ui_friend_invite.tscn"
)
const lobby_member_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_lobby/components/ui_lobby_member.tscn"
)

@onready var friends_container: VBoxContainer = $FriendsContainer
@onready var members_container: VBoxContainer = $MembersContainer
@onready var private_button: Button = $PrivateButton
@onready var start_button: Button = $StartButton

func _ready() -> void:
	if !NetworkManager.local_user.is_host:
		private_button.hide()
		start_button.hide()
	NetworkManager.steam.lobby.on_members_refreshed.connect(refresh_members)
	NetworkManager.local_user.steam.on_friends_refreshed.connect(refresh_friends)
	refresh_friends()
	refresh_members()

func _enter_tree() -> void:
	if !NetworkManager.local_user.is_host:
		private_button.hide()
		start_button.hide()

func refresh_members() -> void:
	for child: Node in members_container.get_children():
		child.queue_free()
	for member_id in NetworkManager.steam.lobby.members.keys():
		var lobby_member_instance = lobby_member_component.instantiate()
		lobby_member_instance.member = NetworkManager.steam.lobby.members[member_id]
		members_container.add_child(lobby_member_instance)
	refresh_friends()

func refresh_friends() -> void:
	for child: Node in friends_container.get_children():
		child.queue_free()
	for friend: SteamUser in NetworkManager.local_user.steam.friends:
		if NetworkManager.steam.lobby.members[friend.id]:
			continue
		var friend_invite_instance = friend_invite_component.instantiate()
		friend_invite_instance.friend = friend
		friends_container.add_child(friend_invite_instance)

func _on_back_button_pressed() -> void:
	NetworkManager.steam.lobby.leave()
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")

func _on_private_button_toggled(private: bool) -> void:
	NetworkManager.steam.lobby.set_private(private)
	private_button.text = "Private" if private else "Friends only"

func _on_start_button_pressed() -> void:
	NetworkManager.start_game()
