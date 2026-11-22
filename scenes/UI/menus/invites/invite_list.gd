extends VBoxContainer
## Invitations received and not answered yet. They are kept by the lobby service,
## so they survive scene changes.

const ROW_SCENE: PackedScene = preload("invite_row.tscn")

var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)
	visible = _lobby.supports_invites
	_lobby.invites_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for child: Node in get_children():
		child.queue_free()
	for lobby_invite: LobbyInvite in _lobby.invites:
		var row: LobbyInviteRow = ROW_SCENE.instantiate() as LobbyInviteRow
		row.setup(_lobby, lobby_invite)
		add_child(row)
