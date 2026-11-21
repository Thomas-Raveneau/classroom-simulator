extends LobbyService
## The `Lobby` autoload: a LobbyService assembled from the project configuration.
##
## - Configuration: the LobbyConfig resource at `res://config/lobby_config.tres`.
## - Backend: `LobbyConfig.default_backend`, or the command line argument
##   `--lobby-backend=<name>` ("steam" or "enet").
## - Scene loader: the `SceneLoader` autoload.
## - Debug builds only: `--net-latency=<ms>`, `--net-jitter=<ms>` and `--net-loss=<%>`
##   simulate a bad connection for this instance (see NetworkConditions).

const CONFIG_PATH: String = "res://config/lobby_config.tres"
const BACKEND_ARGUMENT: String = "--lobby-backend="
const SCENE_LOADER_PATH: NodePath = ^"/root/SceneLoader"
## Backends are loaded by path: the Steam one only compiles when GodotSteam is installed.
const BACKEND_SCRIPTS: Dictionary[String, String] = {
	"steam": "res://network/lobby/backends/steam/steam_lobby_backend.gd",
	"enet": "res://network/lobby/backends/enet/enet_lobby_backend.gd",
}

## How the voice of the players is recorded with each backend, loaded by path for the
## same reason.
const VOICE_SOURCE_SCRIPTS: Dictionary[String, String] = {
	"steam": "res://network/voice/steam_voice_source.gd",
	"enet": "res://network/voice/microphone_voice_source.gd",
}

## Engine class a backend cannot work without (provided by an extension).
const BACKEND_REQUIRED_CLASSES: Dictionary[String, StringName] = {
	"steam": &"SteamMultiplayerPeer",
}

## Null when `LobbyConfig.auto_navigation` is off.
var navigator: LobbyNavigator

func _enter_tree() -> void:
	super()
	var loaded_config: LobbyConfig = _load_config()
	var created_backend: LobbyBackend = _create_backend(loaded_config)
	setup(loaded_config, created_backend, _find_scene_loader(), _create_voice_source(created_backend))
	if OS.is_debug_build():
		network_conditions = NetworkConditions.from_arguments(OS.get_cmdline_args() + OS.get_cmdline_user_args())
		if network_conditions != null:
			print("Lobby: simulating a bad connection (%s)." % network_conditions.describe())
	if loaded_config.auto_navigation:
		navigator = LobbyNavigator.new()
		navigator.name = "Navigator"
		navigator.setup(self)
		add_child(navigator)

func _load_config() -> LobbyConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded_config: LobbyConfig = load(CONFIG_PATH) as LobbyConfig
		if loaded_config != null:
			return loaded_config
	push_warning("Lobby: no LobbyConfig found at %s, using the default settings." % CONFIG_PATH)
	return LobbyConfig.new()

func _create_backend(for_config: LobbyConfig) -> LobbyBackend:
	var backend_name: String = for_config.default_backend
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with(BACKEND_ARGUMENT):
			backend_name = argument.trim_prefix(BACKEND_ARGUMENT)
	var required_class: StringName = BACKEND_REQUIRED_CLASSES.get(backend_name, &"")
	if not required_class.is_empty() and not ClassDB.class_exists(required_class):
		push_error(
			"Lobby: backend \"%s\" needs the GodotSteam extension (addons/godotsteam), which is not installed. Online features are unavailable."
			% backend_name
		)
		return LobbyBackend.new()
	var script_path: String = BACKEND_SCRIPTS.get(backend_name, "")
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script: GDScript = load(script_path) as GDScript
		if script != null and script.can_instantiate():
			var created_backend: LobbyBackend = script.new() as LobbyBackend
			if created_backend != null:
				return created_backend
	push_error("Lobby: backend \"%s\" could not be loaded, online features are unavailable." % backend_name)
	return LobbyBackend.new()

## The voice source that goes with a backend, null when it has none.
func _create_voice_source(for_backend: LobbyBackend) -> VoiceSource:
	var script_path: String = VOICE_SOURCE_SCRIPTS.get(for_backend.get_backend_name(), "")
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		return null
	var script: GDScript = load(script_path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	return script.new() as VoiceSource

func _find_scene_loader() -> LobbySceneLoader:
	var loader: LobbySceneLoader = get_node_or_null(SCENE_LOADER_PATH) as LobbySceneLoader
	if loader == null:
		loader = TreeSceneLoader.new()
		loader.name = "SceneLoader"
		add_child(loader)
	return loader
