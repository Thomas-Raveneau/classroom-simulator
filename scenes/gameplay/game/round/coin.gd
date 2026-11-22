class_name Coin
extends Area3D
## A coin of the collect round. The player who touches it asks the host to collect it:
## the host decides who gets it, since several players can reach it at the same time.

## Time between two requests while the local player keeps touching the coin, in seconds.
const REQUEST_INTERVAL: float = 0.25

var _next_request_at: float = 0.0

func _physics_process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _next_request_at:
		return
	for body: Node3D in get_overlapping_bodies():
		# Each player only asks for its own character.
		if body is Player and body.is_multiplayer_authority():
			_next_request_at = now + REQUEST_INTERVAL
			var actions: HostActions = HostActions.find_for(self)
			if actions != null:
				actions.request(CollectRound.COLLECT_ACTION, [String(name)])
			return
