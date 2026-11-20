class_name LobbyPing
extends Node
## Measures the latency between the host and each member, and publishes it in the data
## of the member (`LobbyMember.ping`, in milliseconds) so everyone can display it.
##
## This node receives RPCs: it must have the same name and path on every peer.

## Time between two measures, in seconds.
const INTERVAL: float = 2.0
## A new value is only published when it differs by at least this much, in milliseconds.
const PUBLISH_THRESHOLD: int = 5

var _members: LobbyMemberSync
var _elapsed: float = INTERVAL
## Host: when the pending request to each peer was sent, in milliseconds.
var _sent_at: Dictionary[int, int] = {}

func setup(members: LobbyMemberSync) -> void:
	_members = members
	_members.member_removed.connect(func(member: LobbyMember) -> void: _sent_at.erase(member.peer_id))

func _process(delta: float) -> void:
	if not _members.is_host():
		return
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = 0.0
	for member: LobbyMember in _members.members.values():
		if member.is_host:
			_publish(member, 0)
		else:
			_sent_at[member.peer_id] = Time.get_ticks_msec()
			_ping.rpc_id(member.peer_id)

@rpc("authority", "call_remote", "unreliable")
func _ping() -> void:
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
