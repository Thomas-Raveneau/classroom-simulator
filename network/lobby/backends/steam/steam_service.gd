extends Node
## Starts the Steam API and runs its callbacks every frame.
## Loaded by the Steam backend only: it needs the GodotSteam extension.

## True once Steam is initialized and usable.
var is_running: bool = false
## Why Steam could not start, as reported by Steam.
var failure_message: String = ""

func start(app_id: int) -> bool:
	# Lets the game find its app id when it is not launched by the Steam client
	# (editor, plain executable).
	OS.set_environment("SteamAppId", str(app_id))
	OS.set_environment("SteamGameId", str(app_id))
	var result: Dictionary = Steam.steamInitEx(app_id, false)
	is_running = result.get("status") == Steam.STEAM_API_INIT_RESULT_OK and Steam.isSubscribed()
	if not is_running:
		failure_message = str(result.get("verbal", "Steam is not available"))
		push_warning("Steam could not start: %s" % failure_message)
	set_process(is_running)
	return is_running

func _process(_delta: float) -> void:
	Steam.run_callbacks()
