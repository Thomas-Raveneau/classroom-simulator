class_name TreeSceneLoader
extends LobbySceneLoader
## Changes the current scene of the tree with a loading screen:
## the scene loads in a background thread, and is shown once loaded, confirmed (optional)
## and after a minimal display time of the loading screen (avoids a flash).
##
## Has no network dependency: usable for any scene change of the game.

const DEFAULT_LOADING_SCREEN: String = "res://scenes/UI/screens/screen_loading.tscn"

## The scene finished loading in the background (it may still wait to be confirmed).
signal loaded(path: String)

## Scene displayed while loading. Falls back to the default loading screen.
var loading_screen_scene: PackedScene
## Minimal time the loading screen stays visible, in seconds.
var minimal_load_time: float = 0.33

var _path: String = ""
var _confirm: Signal
var _is_loaded: bool = false
var _is_confirmed: bool = false
var _is_changing: bool = false
var _elapsed: float = 0.0
var _timeout: float = 0.0
var _loading_screen: Node

func is_loading() -> bool:
	return not _path.is_empty()

func load_scene(path: String, confirm: Signal = Signal(), timeout: float = 0.0) -> void:
	cancel()
	_path = path
	_timeout = timeout
	if confirm.is_null():
		_is_confirmed = true
	else:
		_confirm = confirm
		_confirm.connect(_on_confirmed, CONNECT_ONE_SHOT)
	var error: Error = ResourceLoader.load_threaded_request(path)
	if error != OK:
		_fail()
		return
	_show_loading_screen()
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()

func cancel() -> void:
	if not _confirm.is_null() and _confirm.is_connected(_on_confirmed):
		_confirm.disconnect(_on_confirmed)
	_confirm = Signal()
	_path = ""
	_timeout = 0.0
	_elapsed = 0.0
	_is_loaded = false
	_is_confirmed = false
	_is_changing = false

func _process(delta: float) -> void:
	if _path.is_empty():
		return
	_elapsed += delta
	if _is_changing:
		# change_scene_to_packed() is deferred: wait for the new scene to be in the tree.
		if get_tree().current_scene != null:
			_finish()
		return
	if _timeout > 0.0 and _elapsed >= _timeout:
		_fail()
		return
	if not _poll_loaded() or not _is_confirmed or _elapsed < minimal_load_time:
		return
	var scene: PackedScene = ResourceLoader.load_threaded_get(_path) as PackedScene
	if scene == null or get_tree().change_scene_to_packed(scene) != OK:
		_fail()
		return
	_is_changing = true

func _poll_loaded() -> bool:
	if _is_loaded:
		return true
	match ResourceLoader.load_threaded_get_status(_path):
		ResourceLoader.THREAD_LOAD_LOADED:
			_is_loaded = true
			loaded.emit(_path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail()
	return _is_loaded

func _finish() -> void:
	var path: String = _path
	cancel()
	_hide_loading_screen()
	changed.emit(path)

func _fail() -> void:
	var path: String = _path
	cancel()
	failed.emit(path)

func _show_loading_screen() -> void:
	if _loading_screen != null:
		return
	if loading_screen_scene == null:
		loading_screen_scene = load(DEFAULT_LOADING_SCREEN)
	_loading_screen = loading_screen_scene.instantiate()
	add_child(_loading_screen)

func _hide_loading_screen() -> void:
	if _loading_screen != null:
		_loading_screen.queue_free()
		_loading_screen = null

func _on_confirmed() -> void:
	_is_confirmed = true
