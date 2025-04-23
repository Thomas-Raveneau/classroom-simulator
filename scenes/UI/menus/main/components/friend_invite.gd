extends HBoxContainer

@onready var name_label: Label = $NameLabel

var friend: SteamUser

func _ready() -> void:
	if !friend:
		return
	name_label.text = friend.name

func _on_invite_button_pressed() -> void:
	if !friend:
		return
	SteamManager.lobby.invite(friend)
