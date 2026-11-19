class_name LobbyMemberRow
extends HBoxContainer

@onready var _host_icon: TextureRect = %HostIcon
@onready var _name_label: Label = %NameLabel
@onready var _ready_label: Label = %ReadyLabel
@onready var _kick_button: Button = %KickButton

var _lobby: LobbyService
var _member: LobbyMember

func setup(lobby: LobbyService, member: LobbyMember) -> void:
	_lobby = lobby
	_member = member

func _ready() -> void:
	_name_label.text = _member.name
	# Kept in the layout when hidden, so names stay aligned.
	_host_icon.modulate.a = 1.0 if _member.is_host else 0.0
	_ready_label.visible = _member.is_ready and not _member.is_host
	_kick_button.visible = _lobby.is_host() and _member != _lobby.local_member

func _on_kick_button_pressed() -> void:
	_lobby.kick(_member)
