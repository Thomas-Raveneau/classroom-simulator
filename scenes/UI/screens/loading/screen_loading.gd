class_name LoadingScreen
extends Control

var on_scene_loaded: Signal
var on_scene_failed: Signal
var timeout_seconds: int
var redirect_scene: PackedScene
var fallback_scene: PackedScene
var timeout_timer: Timer

func _ready() -> void:
	on_scene_loaded.connect(_on_loaded)
	if on_scene_failed:
		on_scene_failed.connect(_on_failed)
	if timeout_seconds == 0:
		return
	timeout_timer = Timer.new()
	timeout_timer.autostart = true
	timeout_timer.one_shot = true
	timeout_timer.wait_time = timeout_seconds
	timeout_timer.timeout.connect(_on_failed)
	add_child(timeout_timer)

func setup(
	_on_scene_loaded: Signal,
	_redirect_scene: PackedScene,
	_on_scene_failed: Signal = Signal(),
	_timeout_seconds: int = 20,
	_fallback_scene: PackedScene = load(GameSettings.MAIN_MENU_PATH)
) -> void:
	on_scene_loaded = _on_scene_loaded
	on_scene_failed = _on_scene_failed
	redirect_scene = _redirect_scene
	fallback_scene = _fallback_scene
	timeout_seconds = _timeout_seconds

func _on_loaded() -> void:
	get_tree().change_scene_to_packed(redirect_scene)
	queue_free()

func _on_failed() -> void:
	get_tree().change_scene_to_packed(fallback_scene)
	queue_free()
