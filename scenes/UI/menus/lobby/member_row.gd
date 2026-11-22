class_name LobbyMemberRow
extends HBoxContainer

@onready var _host_icon: TextureRect = %HostIcon
@onready var _name_label: Label = %NameLabel
@onready var _ready_label: Label = %ReadyLabel
@onready var _ping_label: Label = %PingLabel
@onready var _kick_button: Button = %KickButton
@onready var _speaking_label: Label = %SpeakingLabel
@onready var _mute_button: Button = %MuteButton

var _lobby: LobbyService
var _member: LobbyMember

func setup(lobby: LobbyService, member: LobbyMember) -> void:
	_lobby = lobby
	_member = member

func _ready() -> void:
	_name_label.text = _member.name
	# Kept in the layout when hidden, so names stay aligned.
	_host_icon.modulate.a = 1.0 if _member.is_host else 0.0
	_kick_button.visible = _lobby.is_host() and _member != _lobby.local_member
	_mute_button.visible = _lobby.voice.is_enabled() and _member != _lobby.local_member
	_mute_button.set_pressed_no_signal(_lobby.voice.is_member_muted(_member))
	_lobby.voice.speaking_changed.connect(_on_speaking_changed)
	_on_speaking_changed(_member.peer_id, _lobby.voice.is_speaking(_member.peer_id))
	refresh()

## Shows what can change while the member is in the lobby.
func refresh() -> void:
	_ready_label.visible = _member.is_ready and not _member.is_host
	_ping_label.visible = _member.ping >= 0 and not _member.is_host
	_ping_label.text = "%d ms" % _member.ping

func _on_speaking_changed(peer_id: int, is_speaking: bool) -> void:
	if peer_id == _member.peer_id:
		# Kept in the layout when hidden, so the row does not move when someone talks.
		_speaking_label.modulate.a = 1.0 if is_speaking else 0.0

func _on_mute_button_toggled(toggled_on: bool) -> void:
	_lobby.voice.set_member_muted(_member, toggled_on)

func _on_kick_button_pressed() -> void:
	_lobby.kick(_member)
