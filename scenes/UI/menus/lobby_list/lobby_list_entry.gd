class_name LobbyListEntry
extends HBoxContainer

@onready var _name_label: Label = %NameLabel
@onready var _count_label: Label = %CountLabel
@onready var _join_button: Button = %JoinButton

var _lobby: LobbyService
var _info: LobbyInfo

func setup(lobby: LobbyService, info: LobbyInfo) -> void:
	_lobby = lobby
	_info = info

func _ready() -> void:
	_name_label.text = _info.name
	if _info.has_friend:
		_name_label.text += "  (friend)"
	if _info.in_game:
		_name_label.text += "  (in game)"
	var is_full: bool = _info.max_members > 0 and _info.member_count >= _info.max_members
	_count_label.visible = _info.max_members > 0 and _info.member_count > 0
	_count_label.text = "%d/%d" % [_info.member_count, _info.max_members]
	_join_button.disabled = is_full

func _on_join_button_pressed() -> void:
	_lobby.join(_info.id)
