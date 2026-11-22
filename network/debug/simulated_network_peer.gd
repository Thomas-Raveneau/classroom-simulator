class_name SimulatedNetworkPeer
extends MultiplayerPeerExtension
## Debug tool: a connection that behaves like a bad one. It wraps the real connection of
## any backend and delays, shuffles and drops what goes through it, as `conditions` say.
##
## The game does not see the difference with a real bad connection: the lobby service
## installs it in place of the real one when it has `network_conditions`.
##
## What it reproduces, in both directions:
## - latency and jitter, on everything;
## - loss: unreliable packets are dropped, reliable ones arrive late (a resend);
## - order: reliable packets stay in order, "unreliable ordered" ones are dropped when a
##   newer one already went through, plain unreliable ones can overtake each other.
## A disconnection is only reported once everything received before it was delivered,
## and the order to disconnect a peer travels with the same delay as the packets.

## Extra delay of a reliable packet that was "lost", on top of a round trip: roughly
## what a transport waits before sending it again. In milliseconds.
const RESEND_MARGIN_MSEC: float = 50.0
## A reliable packet is not lost more times in a row than this.
const MAX_RESENDS: int = 5

enum Direction { OUTGOING, INCOMING }

class Packet:
	## Outgoing: the target. Incoming: the sender.
	var peer: int = 0
	var channel: int = 0
	var mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var data: PackedByteArray
	var due_msec: float = 0.0
	var sequence: int = 0

var conditions: NetworkConditions

var _inner: MultiplayerPeer
var _outgoing: Array[Packet] = []
var _incoming: Array[Packet] = []
## Received and past their delay: what the multiplayer API reads.
var _deliverable: Array[Packet] = []
var _target_peer: int = 0
var _channel: int = 0
var _mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
## Peers of the real connection.
var _connected_peers: Dictionary[int, bool] = {}
## Peers the real connection lost, not reported yet: some of their packets are pending.
var _departures: Array[int] = []
## Peers being disconnected from here: when the order reaches the real connection, in
## milliseconds, and whether it was a forced one (no disconnection is reported then).
var _disconnections: Dictionary[int, float] = {}
var _forced_disconnections: Dictionary[int, bool] = {}
## Per lane (direction, peer, channel, mode): when its last reliable packet is due.
var _lane_due: Dictionary[Vector4i, float] = {}
## Per lane: sequence of the newest "unreliable ordered" packet that went through.
var _lane_passed: Dictionary[Vector4i, int] = {}
var _sequence: int = 0
var _was_connected: bool = false
var _unique_id: int = 0
var _is_relay_supported: bool = false

func _init(inner: MultiplayerPeer, with_conditions: NetworkConditions) -> void:
	_inner = inner
	conditions = with_conditions if with_conditions != null else NetworkConditions.new()
	_inner.peer_connected.connect(_on_inner_peer_connected)
	_inner.peer_disconnected.connect(_on_inner_peer_disconnected)
	_remember_identity()

## Sends at once what is still waiting for its delay. To call before the real
## connection is closed: what was sent before leaving is already on its way on a real
## network.
func flush() -> void:
	var pending: Array[Packet] = _outgoing
	_outgoing = []
	for packet: Packet in pending:
		_send(packet)

# --- MultiplayerPeer ---------------------------------------------------------------------

func _poll() -> void:
	var now: float = _now()
	if _inner.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		# The real connection sends here what the previous poll gave it: before the
		# disconnections below, which would discard it.
		_inner.poll()
		_remember_identity()
		_apply_due_disconnections(now)
		while _inner.get_available_packet_count() > 0:
			var packet: Packet = Packet.new()
			packet.peer = _inner.get_packet_peer()
			packet.channel = _inner.get_packet_channel()
			packet.mode = _inner.get_packet_mode()
			packet.data = _inner.get_packet()
			# A transport drops what comes from a peer it is disconnecting.
			if _connected_peers.has(packet.peer) and not _disconnections.has(packet.peer):
				_schedule(packet, Direction.INCOMING, now)
		for packet: Packet in _take_due(_outgoing, Direction.OUTGOING, now):
			_send(packet)
	else:
		_outgoing.clear()
		_disconnections.clear()
	_deliverable.append_array(_take_due(_incoming, Direction.INCOMING, now))
	_report_departures()

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _inner.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		# Sent on a connection that already ended, but not reported as such yet: lost.
		return OK if _get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED else ERR_UNCONFIGURED
	var packet: Packet = Packet.new()
	packet.peer = _target_peer
	packet.channel = _channel
	packet.mode = _mode
	packet.data = buffer
	# Nothing waiting and nothing to simulate: exactly the real connection.
	if not conditions.is_active() and _outgoing.is_empty():
		return _send(packet)
	_schedule(packet, Direction.OUTGOING, _now())
	return OK

func _get_packet_script() -> PackedByteArray:
	if _deliverable.is_empty():
		return PackedByteArray()
	var packet: Packet = _deliverable.pop_front()
	return packet.data

func _get_available_packet_count() -> int:
	return _deliverable.size()

func _get_packet_peer() -> int:
	return _deliverable[0].peer if not _deliverable.is_empty() else 0

func _get_packet_channel() -> int:
	return _deliverable[0].channel if not _deliverable.is_empty() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _deliverable[0].mode if not _deliverable.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _get_max_packet_size() -> int:
	return _inner.get_max_packet_size()

func _set_target_peer(peer: int) -> void:
	_target_peer = peer

func _set_transfer_channel(channel: int) -> void:
	_channel = channel

func _get_transfer_channel() -> int:
	return _channel

func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode

func _get_unique_id() -> int:
	return _unique_id

func _is_server() -> bool:
	return _unique_id == MultiplayerPeer.TARGET_PEER_SERVER

func _is_server_relay_supported() -> bool:
	return _is_relay_supported

func _set_refuse_new_connections(enable: bool) -> void:
	_inner.refuse_new_connections = enable

func _is_refusing_new_connections() -> bool:
	return _inner.refuse_new_connections

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	var status: MultiplayerPeer.ConnectionStatus = _inner.get_connection_status()
	# The real connection ended, but what it received before is still on its way.
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED and _was_connected and _has_pending_arrivals():
		return MultiplayerPeer.CONNECTION_CONNECTED
	return status

func _disconnect_peer(peer: int, force: bool) -> void:
	_forget_arrivals_of(peer)
	if force:
		_departures.erase(peer)
	if not _connected_peers.has(peer) or _disconnections.has(peer):
		return
	# The order travels like a packet: what was sent to that peer before still reaches
	# it first, as on a real network.
	_disconnections[peer] = _now() + conditions.latency_ms * 0.5
	_forced_disconnections[peer] = force
	if not conditions.is_active():
		_apply_due_disconnections(_now())

func _close() -> void:
	flush()
	_incoming.clear()
	_deliverable.clear()
	_departures.clear()
	_disconnections.clear()
	_connected_peers.clear()
	_was_connected = false
	_inner.close()

# --- Simulation --------------------------------------------------------------------------

## Decides when a packet goes through, or drops it.
func _schedule(packet: Packet, direction: Direction, now: float) -> void:
	var one_way: float = conditions.latency_ms * 0.5
	var delay: float = one_way + randf() * conditions.jitter_ms
	var is_reliable: bool = packet.mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var resends: int = 0
	while randf() * 100.0 < conditions.loss_percent:
		if not is_reliable:
			return
		if resends == MAX_RESENDS:
			break
		resends += 1
		delay += one_way * 2.0 + RESEND_MARGIN_MSEC
	_sequence += 1
	packet.sequence = _sequence
	packet.due_msec = now + delay
	if is_reliable:
		# A late reliable packet holds back the ones sent after it.
		var lane: Vector4i = _lane_of(packet, direction)
		packet.due_msec = maxf(packet.due_msec, _lane_due.get(lane, 0.0))
		_lane_due[lane] = packet.due_msec
	var queue: Array[Packet] = _outgoing if direction == Direction.OUTGOING else _incoming
	queue.append(packet)

## Removes from `queue` the packets whose delay is over and returns them, oldest first.
func _take_due(queue: Array[Packet], direction: Direction, now: float) -> Array[Packet]:
	var due: Array[Packet] = []
	if queue.is_empty():
		return due
	var waiting: Array[Packet] = []
	for packet: Packet in queue:
		if packet.due_msec > now:
			waiting.append(packet)
			continue
		if packet.mode == MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
			var lane: Vector4i = _lane_of(packet, direction)
			if packet.sequence < _lane_passed.get(lane, 0):
				continue
			_lane_passed[lane] = packet.sequence
		due.append(packet)
	queue.assign(waiting)
	return due

func _send(packet: Packet) -> Error:
	if _inner.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var target: int = packet.peer
	if target > 0 and not _connected_peers.has(target):
		return OK
	if target < 0 and not _connected_peers.has(-target):
		# The peer to leave out is gone: everyone else gets it.
		target = 0
	_inner.transfer_channel = packet.channel
	_inner.transfer_mode = packet.mode
	if target > 0 or _disconnections.is_empty():
		_inner.set_target_peer(target)
		return _inner.put_packet(packet.data)
	# Sent to several peers: not to the ones being disconnected.
	for peer: int in _connected_peers:
		if peer != -target and not _disconnections.has(peer):
			_inner.set_target_peer(peer)
			_inner.put_packet(packet.data)
	return OK

## Disconnects from the real connection the peers whose order had the time to travel.
func _apply_due_disconnections(now: float) -> void:
	for peer: int in _disconnections.keys():
		if _disconnections[peer] > now:
			continue
		var force: bool = _forced_disconnections.get(peer, false)
		_disconnections.erase(peer)
		_forced_disconnections.erase(peer)
		if not _connected_peers.has(peer):
			continue
		_connected_peers.erase(peer)
		_inner.disconnect_peer(peer, force)
		if not force:
			# The transport does not always report a disconnection it started.
			_note_departure(peer)

func _lane_of(packet: Packet, direction: Direction) -> Vector4i:
	return Vector4i(direction, packet.peer, packet.channel, packet.mode)

func _has_pending_arrivals() -> bool:
	return not (_incoming.is_empty() and _deliverable.is_empty() and _departures.is_empty())

func _has_arrivals_of(peer: int) -> bool:
	for packet: Packet in _incoming:
		if packet.peer == peer:
			return true
	for packet: Packet in _deliverable:
		if packet.peer == peer:
			return true
	return false

func _forget_arrivals_of(peer: int) -> void:
	_incoming.assign(_incoming.filter(func(packet: Packet) -> bool: return packet.peer != peer))
	_deliverable.assign(_deliverable.filter(func(packet: Packet) -> bool: return packet.peer != peer))

## Tells the multiplayer API about the peers that left, once it has read all they sent.
func _report_departures() -> void:
	for peer: int in _departures.duplicate():
		if not _has_arrivals_of(peer):
			_departures.erase(peer)
			peer_disconnected.emit(peer)

func _remember_identity() -> void:
	if _inner.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_was_connected = _was_connected or _inner.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	_unique_id = _inner.get_unique_id()
	# Asked again while the last packets of a closed connection are delivered.
	_is_relay_supported = _inner.is_server_relay_supported()

func _on_inner_peer_connected(peer: int) -> void:
	_connected_peers[peer] = true
	peer_connected.emit(peer)

func _on_inner_peer_disconnected(peer: int) -> void:
	if _connected_peers.has(peer):
		_connected_peers.erase(peer)
		_disconnections.erase(peer)
		_note_departure(peer)

func _note_departure(peer: int) -> void:
	if not _departures.has(peer):
		_departures.append(peer)

func _now() -> float:
	return Time.get_ticks_usec() / 1000.0
