extends LobbyService
## The `Lobby` autoload: a LobbyService assembled from the project configuration.
##
## - Configuration: the LobbyConfig resource at the project setting
##   `steam_lobby/config_path` (default `res://lobby_config.tres`).
## - Backend: `LobbyConfig.default_backend`, or the command line argument
##   `--lobby-backend=<name>` ("steam" or "enet").
## - Scene loader: the `SceneLoader` autoload.

const CONFIG_SETTING: String = "steam_lobby/config_path"
const DEFAULT_CONFIG_PATH: String = "res://lobby_config.tres"
const BACKEND_ARGUMENT: String = "--lobby-backend="
const SCENE_LOADER_PATH: NodePath = ^"/root/SceneLoader"
## Backends are loaded by path: the Steam one only compiles when GodotSteam is installed.
const BACKEND_SCRIPTS: Dictionary[String, String] = {
	"steam": "res://addons/steam_lobby/backends/steam/steam_lobby_backend.gd",
	"enet": "res://addons/steam_lobby/backends/enet/enet_lobby_backend.gd",
}

## Null when `LobbyConfig.auto_navigation` is off.
var navigator: LobbyNavigator

func _enter_tree() -> void:
	super()
	var loaded_config: LobbyConfig = _load_config()
	setup(loaded_config, _create_backend(loaded_config), _find_scene_loader())
	if loaded_config.auto_navigation:
		navigator = LobbyNavigator.new()
		navigator.name = "Navigator"
		navigator.setup(self)
		add_child(navigator)

func _load_config() -> LobbyConfig:
	var path: String = ProjectSettings.get_setting(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	if ResourceLoader.exists(path):
		var loaded_config: LobbyConfig = load(path) as LobbyConfig
		if loaded_config != null:
			return loaded_config
	push_warning("Lobby: no LobbyConfig found at %s, using the default settings." % path)
	return LobbyConfig.new()

func _create_backend(for_config: LobbyConfig) -> LobbyBackend:
	var backend_name: String = for_config.default_backend
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with(BACKEND_ARGUMENT):
			backend_name = argument.trim_prefix(BACKEND_ARGUMENT)
	var script_path: String = BACKEND_SCRIPTS.get(backend_name, "")
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script: GDScript = load(script_path) as GDScript
		if script != null and script.can_instantiate():
			var created_backend: LobbyBackend = script.new() as LobbyBackend
			if created_backend != null:
				return created_backend
	push_error("Lobby: backend \"%s\" could not be loaded, online features are unavailable." % backend_name)
	return LobbyBackend.new()

func _find_scene_loader() -> LobbySceneLoader:
	var loader: LobbySceneLoader = get_node_or_null(SCENE_LOADER_PATH) as LobbySceneLoader
	if loader == null:
		loader = TreeSceneLoader.new()
		loader.name = "SceneLoader"
		add_child(loader)
	return loader
