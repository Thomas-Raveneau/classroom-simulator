class_name LobbyBackend
extends Node
## Base class of a lobby backend: the service that provides lobbies, identities and the
## network transport (Steam, ENet...).
##
## A backend never references the lobby service nor the UI. It reports through signals,
## always asynchronously: never emit from inside the method that triggered the operation.
##
## Joining is a two-step contract: the backend reports `lobby_joined` once the backend
## lobby is entered and the transport is connecting; the lobby service then waits for the
## network connection and for the host to admit the player.

## The lobby exists and the transport is hosting.
signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: LobbyTypes.Reason)
## The backend lobby is entered and the transport is connecting to the host.
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: LobbyTypes.Reason)
## The lobby cannot be used anymore (e.g. its owner changed after the host left).
signal lobby_closed(reason: LobbyTypes.Reason)
## Something outside the game asks to join a lobby (invite accepted in the Steam overlay,
## game launched from an invite).
signal join_requested(lobby_id: int)
signal invite_received(invite: LobbyInvite)
signal lobby_list_received(lobbies: Array[LobbyInfo])
signal friends_changed

## Capabilities, read by the UI to hide what the backend cannot do.
var supports_invites: bool = false
var supports_friends: bool = false
var supports_invite_overlay: bool = false

var config: LobbyConfig

func setup(_config: LobbyConfig) -> void:
	config = _config

## False when the backend cannot work (e.g. Steam is not running).
## The base class is the "no backend" backend: it is never available.
func is_available() -> bool:
	return false

## Human readable name, for logs and debug displays.
func get_backend_name() -> String:
	return "none"

func create(_visibility: LobbyTypes.Visibility) -> void:
	_emit_deferred(lobby_create_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)

func join(_lobby_id: int) -> void:
	_emit_deferred(lobby_join_failed, LobbyTypes.Reason.BACKEND_UNAVAILABLE)

## Leaves the backend lobby and closes the transport. Must be safe to call at any time.
func leave() -> void:
	pass

## The transport of the current lobby, null when there is none.
func get_peer() -> MultiplayerPeer:
	return null

## Identity of the local user: { "user_id": int, "name": String }.
func get_local_identity() -> Dictionary:
	return { "user_id": 0, "name": "" }

## Host only. Returns the identity of a connected peer: { "user_id": int, "name": String },
## or an empty dictionary when it cannot be established (the peer is then refused).
## `claim` is what the peer says about itself: only trust it when the backend
## has no way to verify identities.
func resolve_identity(_peer_id: int, _claim: Dictionary) -> Dictionary:
	return {}

## Host only. Allows or forbids new players to join.
func set_joinable(_joinable: bool) -> void:
	pass

## Host only.
func set_visibility(_visibility: LobbyTypes.Visibility) -> void:
	pass

## Host only. Data readable from outside the lobby (lobby lists).
func set_lobby_data(_key: String, _value: String) -> void:
	pass

func invite(_user_id: int) -> void:
	pass

func open_invite_overlay() -> void:
	pass

func get_friends() -> Array[LobbyUser]:
	return []

## Answers with `lobby_list_received`.
func request_lobby_list() -> void:
	var lobbies: Array[LobbyInfo] = []
	_emit_deferred(lobby_list_received, lobbies)

func _emit_deferred(target: Signal, argument: Variant = null) -> void:
	if argument == null:
		target.emit.call_deferred()
	else:
		target.emit.call_deferred(argument)
