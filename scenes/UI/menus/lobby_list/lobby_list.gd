extends Control
## Default lobby browser: lists the lobbies given by the backend (friends' lobbies and
## public lobbies with Steam) and refreshes regularly.

const ENTRY_SCENE: PackedScene = preload("lobby_list_entry.tscn")

@onready var _entries: VBoxContainer = %Entries
@onready var _empty_label: Label = %EmptyLabel
@onready var _refresh_button: Button = %RefreshButton

var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)
	_lobby.lobby_list_received.connect(_show_lobbies)
	_request()

func _request() -> void:
	_refresh_button.disabled = true
	_lobby.request_lobby_list()

func _show_lobbies(lobbies: Array[LobbyInfo]) -> void:
	_refresh_button.disabled = false
	_empty_label.visible = lobbies.is_empty()
	for child: Node in _entries.get_children():
		child.queue_free()
	for info: LobbyInfo in lobbies:
		var entry: LobbyListEntry = ENTRY_SCENE.instantiate() as LobbyListEntry
		entry.setup(_lobby, info)
		_entries.add_child(entry)

func _on_refresh_button_pressed() -> void:
	_request()

func _on_refresh_timer_timeout() -> void:
	_request()

func _on_back_button_pressed() -> void:
	_lobby.scene_loader.load_scene(_lobby.config.main_menu_scene)
