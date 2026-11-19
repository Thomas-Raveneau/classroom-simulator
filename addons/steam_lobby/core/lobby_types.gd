class_name LobbyTypes
## Shared enums of the lobby kit.

## Where the local player stands in the lobby lifecycle.
enum State {
	NONE,       ## Not in a lobby.
	CREATING,   ## Asked the backend to create a lobby.
	JOINING,    ## Joining: backend lobby, network connection, then admission by the host.
	IN_LOBBY,   ## Admitted, waiting in the lobby.
	LOADING,    ## The host ordered a scene, loading in progress.
	IN_GAME,    ## Game scene loaded on every admitted player.
}

## Who can see and join a lobby.
enum Visibility { PRIVATE, FRIENDS_ONLY, PUBLIC }

## Why a lobby was left, or why creating / joining one failed.
enum Reason {
	NONE,
	VOLUNTARY,            ## The local player chose to leave.
	HOST_LEFT,            ## The host closed the lobby or the connection to the host dropped.
	KICKED,
	BANNED,               ## Kicked earlier in this session.
	LOBBY_FULL,
	GAME_IN_PROGRESS,     ## The game started and joining in progress is disabled.
	VERSION_MISMATCH,     ## Different game key or protocol version.
	NOT_FOUND,            ## The lobby does not exist (anymore).
	CONNECTION_FAILED,
	TIMEOUT,
	LOAD_FAILED,          ## A scene could not be loaded in time.
	BACKEND_UNAVAILABLE,  ## E.g. Steam is not running.
	BACKEND_ERROR,
}

const _REASON_TEXTS: Dictionary[Reason, String] = {
	Reason.NONE: "",
	Reason.VOLUNTARY: "",
	Reason.HOST_LEFT: "The host left the lobby.",
	Reason.KICKED: "You were kicked from the lobby.",
	Reason.BANNED: "You cannot rejoin this lobby.",
	Reason.LOBBY_FULL: "The lobby is full.",
	Reason.GAME_IN_PROGRESS: "The game has already started.",
	Reason.VERSION_MISMATCH: "This lobby runs a different version of the game.",
	Reason.NOT_FOUND: "The lobby no longer exists.",
	Reason.CONNECTION_FAILED: "Could not connect to the lobby.",
	Reason.TIMEOUT: "The lobby did not answer in time.",
	Reason.LOAD_FAILED: "Loading took too long.",
	Reason.BACKEND_UNAVAILABLE: "The online service is unavailable.",
	Reason.BACKEND_ERROR: "The online service returned an error.",
}

## Default (English) message for a reason. Empty when nothing needs to be shown.
static func reason_text(reason: Reason) -> String:
	return _REASON_TEXTS.get(reason, "")
