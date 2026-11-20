class_name HostActions
extends Node
## "The player asks, the host decides": the way to do anything that matters for the
## match (pick up, hit, interact, respawn) so that every player agrees on the outcome.
##
## Add one to the game scene, then on every player:
##     actions.register(&"collect", _can_collect, _collect)
## and from the player who acts:
##     actions.request(&"collect", [coin.name])
## The host looks up who is asking from the network connection (never from the message),
## calls `_can_collect(member, arguments)`, and when it returns true `_collect(member, arguments)`.
## What `_collect` changes on the host then reaches everyone through what is already
## replicated: a freed object, a score in MatchState...
##
## Arguments come from another machine: check their number and types in the validator,
## and only send types that go over the network (a node name or path, not a node).
##
## This node receives RPCs: it must have the same name and path on every player.

## Host: an action was accepted and applied.
signal action_applied(action: StringName, member: LobbyMember, arguments: Array)
## Host: an action was refused by its validator or asked too often.
signal action_refused(action: StringName, member: LobbyMember, arguments: Array)

var _validators: Dictionary[StringName, Callable] = {}
var _appliers: Dictionary[StringName, Callable] = {}
var _cooldowns: Dictionary[StringName, float] = {}
var _relayed: Dictionary[StringName, bool] = {}
## Host: last time each member was granted each action, in seconds. Key: [peer id, action].
var _last_granted: Dictionary[Array, float] = {}
var _lobby: LobbyService

func _ready() -> void:
	_lobby = LobbyService.for_node(self)

## Declares an action. Call it on every player, typically in `_ready()`.
## - `validate`: `func(member: LobbyMember, arguments: Array) -> bool`, runs on the host.
## - `apply`: `func(member: LobbyMember, arguments: Array) -> void`, runs on the host once
##   validated.
## - `cooldown`: minimal time in seconds between two grants to the same player.
## - `relay`: also run `apply` on every other player, for what is not replicated otherwise
##   (a sound, an effect). `member` is then null if the player left in the meantime.
func register(
	action: StringName, validate: Callable, apply: Callable, cooldown: float = 0.0, relay: bool = false
) -> void:
	_validators[action] = validate
	_appliers[action] = apply
	_cooldowns[action] = cooldown
	_relayed[action] = relay

## Asks the host to perform an action for the local player.
func request(action: StringName, arguments: Array = []) -> void:
	if _lobby == null or _lobby.local_member == null:
		return
	if multiplayer.is_server():
		_handle(_lobby.local_member, action, arguments)
	else:
		_request.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, action, arguments)

@rpc("any_peer", "call_remote", "reliable")
func _request(action: StringName, arguments: Array) -> void:
	if not multiplayer.is_server() or _lobby == null:
		return
	var member: LobbyMember = _lobby.get_member(multiplayer.get_remote_sender_id())
	# Only a member who is actually in the game can act.
	if member != null and _lobby.is_member_scene_ready(member):
		_handle(member, action, arguments)

func _handle(member: LobbyMember, action: StringName, arguments: Array) -> void:
	if not _validators.has(action):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var grant_key: Array = [member.peer_id, action]
	var is_too_soon: bool = now - _last_granted.get(grant_key, -INF) < _cooldowns[action]
	if is_too_soon or _validators[action].call(member, arguments) != true:
		action_refused.emit(action, member, arguments)
		return
	_last_granted[grant_key] = now
	_appliers[action].call(member, arguments)
	if _relayed[action]:
		for peer_id: int in _lobby.scene_ready_peers:
			if peer_id != multiplayer.get_unique_id():
				_applied.rpc_id(peer_id, action, member.peer_id, arguments)
	action_applied.emit(action, member, arguments)

@rpc("authority", "call_remote", "reliable")
func _applied(action: StringName, peer_id: int, arguments: Array) -> void:
	if _appliers.has(action) and _lobby != null:
		_appliers[action].call(_lobby.get_member(peer_id), arguments)
