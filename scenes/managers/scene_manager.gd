extends Node

signal loaded
signal changed

var loading_screen_scene: PackedScene = preload("res://scenes/UI/screens/screen_loading.tscn")

var scene_path: String = ""
var confirm_load: Signal
var is_loaded: bool = false
var is_changing: bool = false
var is_load_confirmed: bool = false
var previous_scene_id: int = 0
var timeout_timer: Timer
var loading_screen_instance: Node

func _ready() -> void:
	NetworkManager.steam.lobby.on_left.connect(load_main_menu)

func _process(_delta: float) -> void:
	if scene_path.is_empty():
		return
	if !is_scene_loaded():
		return
	if !is_load_confirmed:
		return
	if is_changing && get_tree().current_scene:
		changed.emit()
		reset()
		return
	change_to_loaded_scene()

func load_main_menu() -> void:
	load_scene(GameSettings.MAIN_MENU_PATH)

func reset() -> void:
	if timeout_timer:
		timeout_timer.queue_free()
		timeout_timer = null
	if loading_screen_instance:
		loading_screen_instance.queue_free()
		loading_screen_instance = null
	if confirm_load && confirm_load.is_connected(_on_load_confirmed):
		confirm_load.disconnect(_on_load_confirmed)
		confirm_load = Signal()
	scene_path = ""
	is_loaded = false
	is_changing = false
	is_load_confirmed = false

func cancel_load() -> void:
	reset()
	load_main_menu()

func load_scene(
	_scene_path: String,
	_confirm_load: Signal = Signal(),
	timeout_seconds: int = 30,
) -> void:
	if !scene_path.is_empty():
		push_error("a scene is already being loaded: ", scene_path)
		return
	scene_path = _scene_path
	if _confirm_load:
		confirm_load = _confirm_load
		confirm_load.connect(_on_load_confirmed, CONNECT_ONE_SHOT)
	else:
		is_load_confirmed = true
	if timeout_seconds > 0:
		add_timeout_timer(timeout_seconds)
	ResourceLoader.load_threaded_request(scene_path)
	loading_screen_instance = loading_screen_scene.instantiate()
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	add_child(loading_screen_instance)

func add_timeout_timer(timeout_seconds: int) -> void:
	timeout_timer = Timer.new()
	timeout_timer.autostart = true
	timeout_timer.one_shot = true
	timeout_timer.wait_time = timeout_seconds
	timeout_timer.timeout.connect(_on_load_timeout)
	add_child(timeout_timer)

func is_scene_loaded() -> bool:
	if is_loaded:
		return true
	var progress: Array[float] = []
	var load_status : ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(scene_path, progress)
	if load_status == ResourceLoader.THREAD_LOAD_FAILED \
	|| load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		cancel_load()
		return false
	if load_status != ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
		return false
	loaded.emit()
	is_loaded = true
	return true

func change_to_loaded_scene() -> void:
	if !is_scene_loaded():
		push_error("scene is not loaded: ", scene_path)
		return
	var loaded_scene: PackedScene = ResourceLoader.load_threaded_get(scene_path)
	get_tree().change_scene_to_packed(loaded_scene)
	is_changing = true

func _on_load_confirmed() -> void:
	is_load_confirmed = true

func _on_load_timeout() -> void:
	cancel_load()
