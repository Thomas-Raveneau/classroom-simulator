extends Control
## Default lobby screen: members with their ready state, friends to invite, and the
## controls of the host (visibility, kick, start).

const MEMBER_ROW_SCENE: PackedScene = preload("member_row.tscn")
const FRIEND_ROW_SCENE: PackedScene = preload("friend_row.tscn")
const VISIBILITY_LABELS: Dictionary[LobbyTypes.Visibility, String] = {
	LobbyTypes.Visibility.PRIVATE: "Private (invite only)",
	LobbyTypes.Visibility.FRIENDS_ONLY: "Friends only",
	LobbyTypes.Visibility.PUBLIC: "Public",
}

@onready var _title_label: Label = %TitleLabel
@onready var _members_header: Label = %MembersHeader
@onready var _members: VBoxContainer = %Members
@onready var _friends_panel: Control = %FriendsPanel
@onready var _friends: VBoxContainer = %Friends
@onready var _overlay_button: Button = %OverlayButton
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _visibility_option: OptionButton = %VisibilityOption

var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)
	if not _lobby.is_in_lobby():
		return
	_lobby.member_joined.connect(_refresh.unbind(1))
	_lobby.member_left.connect(_refresh.unbind(1))
	_lobby.member_updated.connect(_refresh.unbind(2))
	# The screen can show while the others are still coming back from a game.
	_lobby.state_changed.connect(_refresh.unbind(1))
	_lobby.friends_changed.connect(_refresh_friends)
	_lobby.lobby_data_changed.connect(_refresh_title.unbind(1))
	_setup_controls()
	_refresh_title()
	_refresh()

func _setup_controls() -> void:
	var is_host: bool = _lobby.is_host()
	_start_button.visible = is_host
	_visibility_option.visible = is_host
	# The host is ready by pressing "Start".
	_ready_button.visible = not is_host
	_ready_button.set_pressed_no_signal(_lobby.local_member.is_ready)
	_friends_panel.visible = _lobby.supports_friends or _lobby.supports_invite_overlay
	_overlay_button.visible = _lobby.supports_invite_overlay
	for visibility: LobbyTypes.Visibility in VISIBILITY_LABELS:
		_visibility_option.add_item(VISIBILITY_LABELS[visibility], visibility)
	_visibility_option.select(_visibility_option.get_item_index(_lobby.visibility))

func _refresh_title() -> void:
	_title_label.text = _lobby.lobby_name

func _refresh() -> void:
	_members_header.text = "Players (%d/%d)" % [_lobby.members.size(), _lobby.config.max_players]
	for child: Node in _members.get_children():
		child.queue_free()
	for member: LobbyMember in _lobby.get_members():
		var row: LobbyMemberRow = MEMBER_ROW_SCENE.instantiate() as LobbyMemberRow
		row.setup(_lobby, member)
		_members.add_child(row)
	_start_button.disabled = not _lobby.can_start_game()
	_refresh_friends()

func _refresh_friends() -> void:
	for child: Node in _friends.get_children():
		child.queue_free()
	if not _lobby.supports_friends:
		return
	var member_user_ids: Array[int] = []
	for member: LobbyMember in _lobby.members.values():
		member_user_ids.append(member.user_id)
	for friend: LobbyUser in _lobby.get_friends():
		if member_user_ids.has(friend.id):
			continue
		var row: LobbyFriendRow = FRIEND_ROW_SCENE.instantiate() as LobbyFriendRow
		row.setup(_lobby, friend)
		_friends.add_child(row)

func _on_leave_button_pressed() -> void:
	_lobby.leave()

func _on_ready_button_toggled(toggled_on: bool) -> void:
	_lobby.set_ready(toggled_on)

func _on_start_button_pressed() -> void:
	_lobby.start_game()

func _on_visibility_option_item_selected(index: int) -> void:
	_lobby.set_visibility(_visibility_option.get_item_id(index) as LobbyTypes.Visibility)

func _on_overlay_button_pressed() -> void:
	_lobby.open_invite_overlay()
