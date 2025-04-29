extends HBoxContainer

@onready var name_label: Label = $NameLabel

var friend: SteamUser

func _ready() -> void:
	if !friend:
		queue_free()
		return
	name_label.text = friend.name

func _on_invite_button_pressed() -> void:
	if !friend:
		return
	NetworkManager.steam.lobby.invite(friend)
