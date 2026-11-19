class_name LobbyFriendRow
extends HBoxContainer

@onready var _name_label: Label = %NameLabel
@onready var _invite_button: Button = %InviteButton

var _lobby: LobbyService
var _friend: LobbyUser

func setup(lobby: LobbyService, friend: LobbyUser) -> void:
	_lobby = lobby
	_friend = friend

func _ready() -> void:
	_name_label.text = _friend.name

func _on_invite_button_pressed() -> void:
	_lobby.invite(_friend.id)
	_invite_button.disabled = true
	_invite_button.text = "Invited"
