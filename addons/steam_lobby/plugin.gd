@tool
extends EditorPlugin
## Registers the autoloads and the project setting of the lobby kit.

const SCENE_LOADER_AUTOLOAD: String = "SceneLoader"
const LOBBY_AUTOLOAD: String = "Lobby"
const CONFIG_SETTING: String = "steam_lobby/config_path"
const DEFAULT_CONFIG_PATH: String = "res://lobby_config.tres"

func _enter_tree() -> void:
	if not ProjectSettings.has_setting(CONFIG_SETTING):
		ProjectSettings.set_setting(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	ProjectSettings.set_initial_value(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	ProjectSettings.add_property_info({
		"name": CONFIG_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res",
	})

func _enable_plugin() -> void:
	# The scene loader first: the lobby uses it.
	add_autoload_singleton(SCENE_LOADER_AUTOLOAD, "res://addons/steam_lobby/scenes/tree_scene_loader.gd")
	add_autoload_singleton(LOBBY_AUTOLOAD, "res://addons/steam_lobby/lobby_autoload.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton(LOBBY_AUTOLOAD)
	remove_autoload_singleton(SCENE_LOADER_AUTOLOAD)
