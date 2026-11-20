class_name LobbyNavigator
extends Node
## Switches between the menu and lobby scenes of `LobbyConfig` by following the signals
## of the lobby service. Created by the `Lobby` autoload when `auto_navigation` is on.
##
## The game scene and the return to the lobby are not handled here: they are loaded on
## every player at once by the lobby service (`start_game()`, `return_to_lobby()`).

var _lobby: LobbyService
## True while the lobby scene is loading and waits for the lobby to be entered.
var _is_entering: bool = false

func setup(lobby: LobbyService) -> void:
	_lobby = lobby
	_lobby.state_changed.connect(_on_state_changed)
	_lobby.entered.connect(_on_entered)
	_lobby.create_failed.connect(_on_attempt_failed)
	_lobby.join_failed.connect(_on_attempt_failed)
	_lobby.left.connect(_on_left)
	_lobby.scene_loader.failed.connect(_on_scene_failed)

func open_main_menu() -> void:
	_lobby.scene_loader.load_scene(_lobby.config.main_menu_scene)

func open_lobby_list() -> void:
	_lobby.scene_loader.load_scene(_lobby.config.lobby_list_scene)

func _on_state_changed(state: LobbyTypes.State) -> void:
	if state == LobbyTypes.State.CREATING or state == LobbyTypes.State.JOINING:
		# The loading screen shows at once; the lobby scene only once the lobby is entered.
		_is_entering = true
		_lobby.scene_loader.load_scene(_lobby.config.lobby_scene, _lobby.entered)

func _on_entered() -> void:
	_is_entering = false

func _on_attempt_failed(_reason: LobbyTypes.Reason) -> void:
	# Nothing to undo when the attempt failed before any scene change (backend unavailable).
	if _is_entering:
		_is_entering = false
		open_main_menu()

func _on_left(_reason: LobbyTypes.Reason) -> void:
	_is_entering = false
	open_main_menu()

func _on_scene_failed(path: String) -> void:
	if path == _lobby.config.main_menu_scene:
		push_error("LobbyNavigator: the main menu scene could not be loaded: %s" % path)
		return
	if _lobby.state != LobbyTypes.State.NONE:
		# Leaving brings back to the main menu.
		_lobby.leave()
	else:
		open_main_menu()
