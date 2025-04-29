extends VBoxContainer

var invites: Array = []

var steam_invite_component: PackedScene = preload(
	"res://scenes/UI/menus/main/steam_invite_list/components/ui_steam_invite.tscn"
)

func _ready() -> void:
	NetworkManager.steam.lobby.on_invite_received.connect(_on_invite_received)

func refresh_invites() -> void:
	if invites.size() == 0:
		return
	for child in get_children():
		child.queue_free()
	for invite in invites:
		add_child(invite)

func _on_invite_received(user: SteamUser, lobby_id: int) -> void:
	var steam_invite_instance: HBoxContainer = steam_invite_component.instantiate()
	steam_invite_instance.user = user
	steam_invite_instance.lobby_id = lobby_id
	invites.push_front(steam_invite_instance)
	refresh_invites()
