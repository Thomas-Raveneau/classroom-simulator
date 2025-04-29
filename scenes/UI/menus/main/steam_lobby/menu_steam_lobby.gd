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
	if !SteamManager.user.is_host:
		private_button.hide()
		start_button.hide()
	SteamManager.lobby.on_members_refreshed.connect(refresh_members)
	SteamManager.user.on_friends_refreshed.connect(refresh_friends)
	refresh_friends()
	refresh_members()

func refresh_members() -> void:
	for child: Node in members_container.get_children():
		child.queue_free()
	for member: SteamUser in SteamManager.lobby.members:
		var lobby_member_instance = lobby_member_component.instantiate()
		lobby_member_instance.member = member
		members_container.add_child(lobby_member_instance)
	refresh_friends()

func refresh_friends() -> void:
	for child: Node in friends_container.get_children():
		child.queue_free()
	for friend: SteamUser in SteamManager.user.friends:
		if SteamManager.lobby.members.any(
			func (member: SteamUser):
				return friend.id == member.id
		):
			continue
		var friend_invite_instance = friend_invite_component.instantiate()
		friend_invite_instance.friend = friend
		friends_container.add_child(friend_invite_instance)

func _on_back_button_pressed() -> void:
	SteamManager.lobby.leave()
	get_tree().change_scene_to_file("res://scenes/UI/menus/main/menu_main.tscn")

func _on_private_button_toggled(private: bool) -> void:
	SteamManager.lobby.set_private(private)
	private_button.text = "Private" if private else "Friends only"

func _on_start_button_pressed() -> void:
	SteamManager.start_game()
