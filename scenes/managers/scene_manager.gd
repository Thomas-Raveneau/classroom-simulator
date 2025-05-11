extends Node

var loading_screen_scene: PackedScene = preload("res://scenes/UI/screens/screen_loading.tscn")

var scene_path: String = ""
var on_load_ready: Signal
var is_ready_to_load: bool = false
var timeout_timer: Timer
var loading_screen_instance: Node

func _ready() -> void:
	NetworkManager.steam.lobby.on_left.connect(load_main_menu)

func _process(_delta: float) -> void:
	if scene_path.is_empty():
		return
	if !is_ready_to_load:
		return
	if !is_scene_loaded():
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
	if on_load_ready && on_load_ready.is_connected(_on_ready_to_load):
		on_load_ready.disconnect(_on_ready_to_load)
		on_load_ready = Signal()
	scene_path = ""
	is_ready_to_load = false

func cancel_load():
	reset()
	load_main_menu()

func load_scene(
	_scene_path: String,
	_on_load_ready: Signal = Signal(),
	timeout_seconds: int = 30,
) -> void:
	if !scene_path.is_empty():
		push_error("a scene is already being loaded: ", scene_path)
		return
	scene_path = _scene_path
	if _on_load_ready:
		on_load_ready = _on_load_ready
		on_load_ready.connect(_on_ready_to_load)
	else:
		is_ready_to_load = true
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
	var progress = []
	var load_status : ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(scene_path, progress)
	if load_status == ResourceLoader.THREAD_LOAD_FAILED \
	|| load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		cancel_load()
		return false
	return load_status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED

func change_to_loaded_scene() -> void:
	if !is_scene_loaded():
		push_error("scene is not loaded: ", scene_path)
		return
	var loaded_scene: PackedScene = ResourceLoader.load_threaded_get(scene_path)
	get_tree().change_scene_to_packed(loaded_scene)
	reset()

func _on_ready_to_load() -> void:
	is_ready_to_load = true

func _on_load_timeout() -> void:
	cancel_load()
