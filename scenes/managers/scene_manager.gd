extends Node

var main_menu_scene: PackedScene = preload(GameSettings.MAIN_MENU_PATH)
var loading_screen_scene: PackedScene = preload("res://scenes/UI/screens/loading/screen_loading.tscn")

func _ready() -> void:
	NetworkManager.steam.lobby.on_left.connect(load_main_menu)

func load_main_menu() -> void:
	get_tree().change_scene_to_packed(main_menu_scene)

func load_scene(
	current_scene: Node, 
	on_scene_loaded: Signal,
	redirect_scene: PackedScene,
	on_scene_failed: Signal = Signal(),
	timeout_seconds: int = 20,
	fallback_scene: PackedScene = load(GameSettings.MAIN_MENU_PATH)
) -> void:
	var loading_screen_instance: LoadingScreen = loading_screen_scene.instantiate()
	loading_screen_instance.setup(
		on_scene_loaded, 
		redirect_scene,
		on_scene_failed,
		timeout_seconds,
		fallback_scene
	)
	add_child(loading_screen_instance)
	current_scene.queue_free()
