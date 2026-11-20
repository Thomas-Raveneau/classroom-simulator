class_name LobbyConfig
extends Resource
## Every setting of the lobby. The game uses the one saved at `res://config/lobby_config.tres`.

const MENUS_DIR: String = "res://scenes/UI/menus/"

@export_group("Lobby")
## Maximum number of players, host included.
@export_range(1, 250) var max_players: int = 10
@export var default_visibility: LobbyTypes.Visibility = LobbyTypes.Visibility.FRIENDS_ONLY
## Identifies your game among the lobbies of the same Steam app.
## Mandatory with the shared test app 480: without it you would list other developers' lobbies.
@export var game_key: String = "steam_lobby_template"
## Bump when builds stop being network compatible: older builds are refused.
@export var protocol_version: int = 1
## Players may join after the game started. When false the lobby is locked during the game.
@export var allow_join_in_progress: bool = false
## The host can only start once every player is ready.
@export var require_all_ready: bool = false
## How long, in seconds, the seat of a player who lost its connection during the game is
## kept: coming back in time, the player gets its data and score back. 0 disables it.
@export_range(0.0, 600.0) var reconnect_grace: float = 60.0

@export_group("Scenes")
@export_file("*.tscn") var main_menu_scene: String = MENUS_DIR + "main_menu/main_menu.tscn"
@export_file("*.tscn") var lobby_list_scene: String = MENUS_DIR + "lobby_list/lobby_list.tscn"
@export_file("*.tscn") var lobby_scene: String = MENUS_DIR + "lobby/lobby.tscn"
## Scene loaded on every player by `Lobby.start_game()`.
@export_file("*.tscn") var game_scene: String = ""
## Let the lobby switch between menu, lobby and game scenes by itself.
## Disable it to drive scene changes from your own code using the signals of `Lobby`.
@export var auto_navigation: bool = true

@export_group("Timeouts (seconds)")
## Maximum time between asking to join and being admitted by the host.
@export_range(1.0, 120.0) var join_timeout: float = 20.0
## Maximum time for all players to load a scene. Late players are removed.
@export_range(1.0, 300.0) var load_timeout: float = 30.0
## Time left to a removed player to leave by itself before its connection is cut.
@export_range(0.1, 10.0) var dismiss_grace: float = 2.0
## A player (or the host) that does not answer for this long is considered disconnected.
## 0 leaves it to the transport, which can take 30 seconds. Keep it above the longest
## freeze a machine can have (first load of a heavy scene): a frozen instance, or one
## paused in the debugger, is dropped after this time. It can then rejoin.
@export_range(0.0, 60.0) var connection_timeout: float = 15.0

@export_group("Backend")
## "steam" or "enet". Overridden by the command line argument `--lobby-backend=<name>`.
@export var default_backend: String = "steam"
@export var steam_app_id: int = 480
## Port of the ENet backend, used to test locally with several windows.
@export_range(1024, 65535) var enet_port: int = 24565
