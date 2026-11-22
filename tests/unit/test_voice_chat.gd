extends LobbyGameTest
## Voice chat between players over a real connection, with a fake microphone: what a
## player "says" is a packet of bytes, heard by the others as one sample per byte.

const HELLO: PackedByteArray = [255, 0, 255]

## What each player heard: [speaker peer id, samples].
var _heard: Dictionary[LobbyTestPeer, Array] = {}

func before_each() -> void:
	super()
	config.voice_activation = LobbyTypes.VoiceActivation.OPEN_MIC
	# Voice is sent without guarantee of delivery, and these tests count packets: they
	# run on a perfect connection whatever the environment asks for. The last network
	# test of the file covers the bad one.
	conditions = NetworkConditions.new()
	_heard = {}

func _listen(test_peer: LobbyTestPeer) -> void:
	_heard[test_peer] = []
	test_peer.service.voice.voice_received.connect(
		func(peer_id: int, samples: PackedFloat32Array) -> void: _heard[test_peer].append([peer_id, samples])
	)

func _lobby_of_three() -> Array[LobbyTestPeer]:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var other: LobbyTestPeer = await add_client()
	for test_peer: LobbyTestPeer in peers:
		_listen(test_peer)
	await until(func() -> bool: return other.service.members.size() == 3, "everyone is in the lobby")
	return peers

func _say(test_peer: LobbyTestPeer, packet: PackedByteArray = HELLO) -> void:
	test_peer.voice_source.spoken.append(packet)

func _heard_count(test_peer: LobbyTestPeer) -> int:
	return _heard[test_peer].size()

func test_voice_of_a_player_is_heard_by_the_others() -> void:
	var players: Array[LobbyTestPeer] = await _lobby_of_three()
	var client: LobbyTestPeer = players[1]
	_say(client)
	await until(func() -> bool: return _heard_count(players[0]) == 1, "host hears the client")
	await until(func() -> bool: return _heard_count(players[2]) == 1, "another client hears it too")
	assert_eq(_heard[players[0]][0][0], client.service.local_member.peer_id, "and knows who talks")
	assert_eq(_heard[players[0]][0][1], PackedFloat32Array([1.0, 0.0, 1.0]), "decoded by the source")
	await wait_seconds(0.2)
	assert_eq(_heard_count(client), 0, "a player does not hear itself")
	_say(players[0])
	await until(func() -> bool: return _heard_count(client) == 1, "the client hears the host")
	assert_engine_error_count(0)

func test_push_to_talk_only_records_while_asked() -> void:
	config.voice_activation = LobbyTypes.VoiceActivation.PUSH_TO_TALK
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	_listen(host)
	await wait_process_frames(3)
	assert_false(client.voice_source.is_capturing, "the microphone is off")
	client.service.voice.is_talk_pressed = true
	await wait_process_frames(3)
	assert_true(client.voice_source.is_capturing, "on while talking")
	_say(client)
	await until(func() -> bool: return _heard_count(host) == 1, "heard while talking")
	client.service.voice.is_talk_pressed = false
	await wait_process_frames(3)
	assert_false(client.voice_source.is_capturing, "off again")

func test_open_microphone_records_as_soon_as_someone_can_hear() -> void:
	var host: LobbyTestPeer = await add_host()
	await wait_process_frames(3)
	assert_false(host.voice_source.is_capturing, "nobody to talk to")
	await add_client()
	await wait_process_frames(3)
	assert_true(host.voice_source.is_capturing)
	host.service.voice.is_microphone_muted = true
	await wait_process_frames(3)
	assert_false(host.voice_source.is_capturing, "muted microphone")

func test_muted_member_is_not_heard() -> void:
	var players: Array[LobbyTestPeer] = await _lobby_of_three()
	var host: LobbyTestPeer = players[0]
	var client: LobbyTestPeer = players[1]
	var client_member: LobbyMember = host.service.get_member(client.service.local_member.peer_id)
	host.service.voice.set_member_muted(client_member, true)
	assert_true(host.service.voice.is_member_muted(client_member))
	_say(client)
	await until(func() -> bool: return _heard_count(players[2]) == 1, "the other client hears it")
	await wait_seconds(0.2)
	assert_eq(_heard_count(host), 0, "not the player who muted it")
	host.service.voice.set_member_muted(client_member, false)
	_say(client)
	await until(func() -> bool: return _heard_count(host) == 1, "heard again once unmuted")

func test_speaking_is_told_and_ends_with_the_voice() -> void:
	var players: Array[LobbyTestPeer] = await _lobby_of_three()
	var host: LobbyTestPeer = players[0]
	var client: LobbyTestPeer = players[1]
	var client_peer_id: int = client.service.local_member.peer_id
	watch_signals(host.service.voice)
	_say(client)
	await until(func() -> bool: return host.service.voice.is_speaking(client_peer_id), "host sees the client talking")
	assert_signal_emitted_with_parameters(host.service.voice, "speaking_changed", [client_peer_id, true])
	assert_true(client.service.voice.is_speaking(client_peer_id), "the client sees itself talking")
	await until(func() -> bool: return not host.service.voice.is_speaking(client_peer_id), "it ends with the voice")
	assert_signal_emitted_with_parameters(host.service.voice, "speaking_changed", [client_peer_id, false])

func test_oversized_and_empty_packets_are_ignored() -> void:
	var players: Array[LobbyTestPeer] = await _lobby_of_three()
	var client: LobbyTestPeer = players[1]
	var huge: PackedByteArray = PackedByteArray()
	huge.resize(VoiceChat.MAX_PACKET_BYTES + 1)
	_say(client, huge)
	_say(client, PackedByteArray())
	# Sent straight to the host, as a modified client would.
	client.service.voice._voice.rpc_id(1, huge)
	_say(client)
	await until(func() -> bool: return _heard_count(players[0]) == 1, "the valid packet is heard")
	await wait_seconds(0.2)
	assert_eq(_heard_count(players[0]), 1, "and nothing else")
	assert_engine_error_count(0)

func test_flood_of_packets_is_capped() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	_listen(host)
	# All within the same second, whatever the frame rate.
	await wait_until(func() -> bool: return Time.get_ticks_msec() % 1000 < 100, 2.0)
	for index: int in VoiceChat.MAX_PACKETS_PER_SECOND * 2:
		client.service.voice._voice.rpc_id(1, HELLO)
	await wait_seconds(0.5)
	assert_between(_heard_count(host), 1, VoiceChat.MAX_PACKETS_PER_SECOND, "no more than a voice needs")

func test_voice_disabled_in_the_configuration() -> void:
	config.voice_enabled = false
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	_listen(host)
	await wait_process_frames(3)
	assert_false(client.service.voice.can_talk())
	assert_false(client.voice_source.is_capturing)
	client.service.voice._voice.rpc_id(1, HELLO)
	await wait_seconds(0.3)
	assert_eq(_heard_count(host), 0)

func test_player_without_microphone_still_hears() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	client.voice_source.available = false
	_listen(client)
	await wait_process_frames(3)
	assert_false(client.service.voice.can_talk())
	assert_false(client.voice_source.is_capturing)
	_say(host)
	await until(func() -> bool: return _heard_count(client) == 1, "hears the host")

func test_voice_comes_out_of_the_character_in_proximity_range() -> void:
	var host: LobbyTestPeer = await add_host()
	var client: LobbyTestPeer = await add_client()
	var voice: VoiceChat = host.service.voice
	var client_peer_id: int = client.service.local_member.peer_id
	var emitter: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	add_child_autofree(emitter)
	voice.register_emitter(client_peer_id, emitter)
	assert_true(voice._output_of(client_peer_id) is AudioStreamPlayer, "heard by everyone in EVERYONE range")
	config.voice_range = LobbyTypes.VoiceRange.PROXIMITY
	assert_eq(voice._output_of(client_peer_id), emitter, "out of the character in PROXIMITY range")
	assert_true(voice._output_of(1) is AudioStreamPlayer, "a player without character is heard by everyone")
	_say(client)
	await until(func() -> bool: return emitter.playing, "the voice is played on the emitter")
	assert_true(emitter.stream is AudioStreamGenerator)
	voice.unregister_emitter(client_peer_id, emitter)
	assert_true(voice._output_of(client_peer_id) is AudioStreamPlayer, "back to everyone without it")

func test_voice_goes_through_a_bad_connection() -> void:
	conditions = NetworkConditions.new()
	conditions.latency_ms = 150
	conditions.jitter_ms = 10
	conditions.loss_percent = 5.0
	var players: Array[LobbyTestPeer] = await _lobby_of_three()
	for index: int in 50:
		_say(players[1], PackedByteArray([index]))
		await wait_process_frames(3)
	await wait_seconds(1.0)
	# From a client to another: through the host, so twice the losses.
	var heard: Array = _heard[players[2]]
	assert_between(heard.size(), 20, 50, "most of it arrives, between clients too")
	var is_in_order: bool = true
	for index: int in range(1, heard.size()):
		var previous: PackedFloat32Array = heard[index - 1][1]
		var current: PackedFloat32Array = heard[index][1]
		is_in_order = is_in_order and current[0] > previous[0]
	assert_true(is_in_order, "never an older piece of voice after a newer one")

func test_pcm_conversion_round_trip() -> void:
	var samples: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, -0.5, 1.0, -1.0])
	var bytes: PackedByteArray = VoiceSource.samples_to_pcm16(samples)
	assert_eq(bytes.size(), 10)
	var back: PackedFloat32Array = VoiceSource.pcm16_to_samples(bytes)
	for index: int in samples.size():
		assert_almost_eq(back[index], samples[index], 0.001)

func test_microphone_source_brings_audio_to_the_voice_rate() -> void:
	var microphone: MicrophoneVoiceSource = autofree(MicrophoneVoiceSource.new())
	var frames: PackedVector2Array = PackedVector2Array()
	for index: int in 4800:
		frames.append(Vector2(0.5, 0.5))
	var samples: PackedFloat32Array = microphone._to_voice_rate(frames, 48000.0)
	assert_eq(samples.size(), 1600, "a third of the frames from 48 kHz to 16 kHz")
	assert_almost_eq(samples[0], 0.5, 0.001, "both channels mixed")
	assert_almost_eq(MicrophoneVoiceSource.loudness(samples), 0.5, 0.001)
	assert_eq(microphone.decode(PackedByteArray([1, 2, 3])).size(), 0, "half a sample is not valid")
