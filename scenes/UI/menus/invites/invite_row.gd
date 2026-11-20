class_name LobbyInviteRow
extends HBoxContainer

@onready var _name_label: Label = %NameLabel

var _lobby: LobbyService
var _invite: LobbyInvite

func setup(lobby: LobbyService, lobby_invite: LobbyInvite) -> void:
	_lobby = lobby
	_invite = lobby_invite

func _ready() -> void:
	_name_label.text = "%s invites you" % _invite.from.name

func _on_accept_button_pressed() -> void:
	_lobby.accept_invite(_invite)

func _on_decline_button_pressed() -> void:
	_lobby.decline_invite(_invite)
