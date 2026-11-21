extends GutTest
## The simulated bad connection alone: a real ENet server on one side, a client wrapped
## in a SimulatedNetworkPeer on the other, polled by hand.

const WAIT: float = 5.0

var _server: ENetMultiplayerPeer
var _client: SimulatedNetworkPeer
var _conditions: NetworkConditions
## What each side received, in order: the first byte of every packet.
var _server_received: Array[int] = []
var _client_received: Array[int] = []

func before_each() -> void:
	var port: int = LobbyTestPeer.pick_port()
	_server = ENetMultiplayerPeer.new()
	_server.create_server(port)
	var real_client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	real_client.create_client("127.0.0.1", port)
	_conditions = NetworkConditions.new()
	_client = SimulatedNetworkPeer.new(real_client, _conditions)
	_server_received = []
	_client_received = []
	# Both sides must know each other before anything is sent.
	var server: ENetMultiplayerPeer = _server
	var seen_by_server: Array[int] = []
	server.peer_connected.connect(func(peer: int) -> void: seen_by_server.append(peer))
	await wait_until(func() -> bool: return _is_client_connected() and not seen_by_server.is_empty(), WAIT)

func after_each() -> void:
	_client.close()
	_server.close()

func _process(_delta: float) -> void:
	if _server == null or _client == null:
		return
	_server.poll()
	while _server.get_available_packet_count() > 0:
		_server_received.append(_server.get_packet()[0])
	_client.poll()
	while _client.get_available_packet_count() > 0:
		_client_received.append(_client.get_packet()[0])

func _is_client_connected() -> bool:
	return _client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _send_from_client(count: int, mode: MultiplayerPeer.TransferMode) -> void:
	_client.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_client.transfer_mode = mode
	for index: int in count:
		_client.put_packet(PackedByteArray([index]))

func _is_increasing(values: Array[int]) -> bool:
	for index: int in range(1, values.size()):
		if values[index] <= values[index - 1]:
			return false
	return true

func test_without_conditions_packets_go_straight_through() -> void:
	assert_true(_is_client_connected(), "connects through the wrapper")
	_send_from_client(3, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	await wait_until(func() -> bool: return _server_received.size() == 3, 0.5)
	assert_eq(_server_received, [0, 1, 2])

func test_latency_delays_what_is_sent() -> void:
	_conditions.latency_ms = 400
	_send_from_client(1, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	await wait_seconds(0.1)
	assert_eq(_server_received.size(), 0, "still on its way after 100 ms")
	await wait_until(func() -> bool: return _server_received.size() == 1, WAIT)
	assert_eq(_server_received, [0], "arrives after the delay")

func test_latency_delays_what_is_received() -> void:
	_conditions.latency_ms = 400
	_server.set_target_peer(_client.get_unique_id())
	_server.put_packet(PackedByteArray([7]))
	await wait_seconds(0.1)
	assert_eq(_client_received.size(), 0, "still on its way after 100 ms")
	await wait_until(func() -> bool: return _client_received.size() == 1, WAIT)
	assert_eq(_client_received, [7])

func test_loss_drops_part_of_the_unreliable_packets() -> void:
	_conditions.loss_percent = 50.0
	_send_from_client(200, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	await wait_seconds(0.5)
	assert_between(_server_received.size(), 50, 150, "about half of them arrive")

func test_reliable_packets_all_arrive_in_order_whatever_the_conditions() -> void:
	_conditions.latency_ms = 60
	_conditions.jitter_ms = 80
	_conditions.loss_percent = 40.0
	_send_from_client(100, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	await wait_until(func() -> bool: return _server_received.size() == 100, WAIT)
	assert_eq(_server_received.size(), 100, "none is lost")
	assert_true(_is_increasing(_server_received), "in the order they were sent")

func test_jitter_shuffles_unreliable_packets() -> void:
	_conditions.jitter_ms = 200
	_send_from_client(100, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	await wait_until(func() -> bool: return _server_received.size() == 100, WAIT)
	assert_eq(_server_received.size(), 100, "jitter alone loses nothing")
	assert_false(_is_increasing(_server_received), "they overtake each other")

func test_ordered_packets_never_arrive_after_a_newer_one() -> void:
	_conditions.jitter_ms = 200
	_send_from_client(100, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	await wait_seconds(0.5)
	assert_gt(_server_received.size(), 0, "some arrive")
	assert_lt(_server_received.size(), 100, "the ones overtaken are dropped")
	assert_true(_is_increasing(_server_received), "never an older one after a newer one")

func test_flush_sends_at_once_what_was_waiting() -> void:
	_conditions.latency_ms = 2000
	_send_from_client(3, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_client.flush()
	await wait_until(func() -> bool: return _server_received.size() == 3, 0.5)
	assert_eq(_server_received, [0, 1, 2])

func test_what_was_received_before_a_disconnection_is_delivered_before_it() -> void:
	_conditions.latency_ms = 600
	var events: Array[String] = []
	_client.peer_disconnected.connect(func(_peer: int) -> void: events.append("disconnected"))
	_server.set_target_peer(_client.get_unique_id())
	_server.put_packet(PackedByteArray([9]))
	_server.host.flush()
	await wait_seconds(0.1)
	_server.disconnect_peer(_client.get_unique_id())
	await wait_seconds(0.1)
	assert_true(_is_client_connected(), "not reported while a packet is still on its way")
	await wait_until(func() -> bool: return not _is_client_connected(), WAIT)
	assert_eq(_client_received, [9], "the packet was delivered")
	assert_eq(events, ["disconnected"], "then the disconnection was reported")
