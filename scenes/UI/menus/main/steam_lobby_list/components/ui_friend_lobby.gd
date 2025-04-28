extends HBoxContainer

@onready var name_label: Label = $NameLabel

var friend_lobby: SteamFriendLobby

func _ready() -> void:
	if !friend_lobby:
		queue_free()
		return
	name_label.text = friend_lobby.name

func _on_join_button_pressed() -> void:
	SteamManager.lobby.join(friend_lobby.id)
