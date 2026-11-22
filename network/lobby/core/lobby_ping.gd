class_name LobbyPing
extends Node
## Measures the latency between the host and each member, and publishes it in the data
## of the member (`LobbyMember.ping`, in milliseconds) so everyone can display it.
##
## The same exchange tells when the other side stopped answering, long before the
## transport gives up (`LobbyConfig.connection_timeout`).
##
## This node receives RPCs: it must have the same name and path on every peer.

## Host: a member did not answer for `connection_timeout`.
signal member_unreachable(peer_id: int)
## Client: nothing came from the host for `connection_timeout`.
signal host_unreachable

## Longest time between two measures, in seconds.
const MAX_INTERVAL: float = 2.0
## A new value is only published when it differs by at least this much, in milliseconds.
const PUBLISH_THRESHOLD: int = 5

var _config: LobbyConfig
var _members: LobbyMemberSync
var _interval: float = MAX_INTERVAL
var _elapsed: float = 0.0
## Host: when the pending request to each peer was sent, in milliseconds.
var _sent_at: Dictionary[int, int] = {}
## Host: requests in a row each peer left unanswered.
var _missed: Dictionary[int, int] = {}
## Client: last time the host was heard, in milliseconds.
var _host_heard_at: int = 0

func setup(config: LobbyConfig, members: LobbyMemberSync) -> void:
	_config = config
	_members = members
	_members.member_removed.connect(_forget)
	_members.admitted.connect(func() -> void: _host_heard_at = Time.get_ticks_msec())
	if _config.connection_timeout > 0.0:
		# Several measures fit in the timeout, so one lost answer is not a disconnection.
		_interval = clampf(_config.connection_timeout / 4.0, 0.05, MAX_INTERVAL)
	_elapsed = _interval

func _process(delta: float) -> void:
	if _members.local_member == null:
		return
	_elapsed += delta
	if _elapsed < _interval:
		return
	_elapsed = 0.0
	if _members.is_host():
		_measure_members()
	elif _has_timed_out(Time.get_ticks_msec() - _host_heard_at):
		_host_heard_at = Time.get_ticks_msec()
		host_unreachable.emit()

func _measure_members() -> void:
	for member: LobbyMember in _members.members.values():
		var peer_id: int = member.peer_id
		if member.is_host:
			_publish(member, 0)
			continue
		_missed[peer_id] = _missed.get(peer_id, 0) + 1 if _sent_at.has(peer_id) else 0
		if _has_timed_out(roundi(_missed[peer_id] * _interval * 1000.0)):
			member_unreachable.emit(peer_id)
			continue
		_sent_at[peer_id] = Time.get_ticks_msec()
		_ping.rpc_id(peer_id)

func _has_timed_out(silence_msec: int) -> bool:
	return _config.connection_timeout > 0.0 and silence_msec >= _config.connection_timeout * 1000.0

func _forget(member: LobbyMember) -> void:
	_sent_at.erase(member.peer_id)
	_missed.erase(member.peer_id)

@rpc("authority", "call_remote", "unreliable")
func _ping() -> void:
	_host_heard_at = Time.get_ticks_msec()
	_pong.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)

@rpc("any_peer", "call_remote", "unreliable")
func _pong() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var member: LobbyMember = _members.get_member(peer_id)
	# Timed by the host alone: nothing the member sends can alter the measure.
	if not _members.is_host() or member == null or not _sent_at.has(peer_id):
		return
	var round_trip: int = Time.get_ticks_msec() - _sent_at[peer_id]
	_sent_at.erase(peer_id)
	_publish(member, round_trip)

func _publish(member: LobbyMember, round_trip: int) -> void:
	if member.ping < 0 or absi(member.ping - round_trip) >= PUBLISH_THRESHOLD:
		_members.set_member_data_as_host(member, LobbyMember.PING_KEY, round_trip)
