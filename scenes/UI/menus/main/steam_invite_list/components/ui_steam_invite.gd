extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var accept_button: Button = $AcceptButton

var user: SteamUser
var lobby_id: int = 0

func _ready() -> void:
	if !user || !user.name || lobby_id == 0:
		queue_free()
		return
	name_label.text = user.name

func _on_accept_button_pressed() -> void:
	NetworkManager.steam.lobby.join(lobby_id)
