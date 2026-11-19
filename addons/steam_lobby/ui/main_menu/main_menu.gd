extends Control
## Default main menu: create a lobby, browse lobbies, answer invitations.
## Also where the player lands after leaving a lobby, with the reason when there is one.

@onready var _create_button: Button = %CreateButton
@onready var _join_button: Button = %JoinButton
@onready var _notice_label: Label = %NoticeLabel

var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)
	_lobby.create_failed.connect(_show_reason)
	_lobby.join_failed.connect(_show_reason)
	if _lobby.is_available():
		_show_reason(_lobby.last_reason)
		_lobby.last_reason = LobbyTypes.Reason.NONE
	else:
		_create_button.disabled = true
		_join_button.disabled = true
		_show_reason(LobbyTypes.Reason.BACKEND_UNAVAILABLE)

func _show_reason(reason: LobbyTypes.Reason) -> void:
	_notice_label.text = LobbyTypes.reason_text(reason)
	_notice_label.visible = not _notice_label.text.is_empty()

func _on_create_button_pressed() -> void:
	_lobby.create()

func _on_join_button_pressed() -> void:
	_lobby.scene_loader.load_scene(_lobby.config.lobby_list_scene)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
