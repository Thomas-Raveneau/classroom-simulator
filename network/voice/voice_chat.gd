class_name VoiceChat
extends Node
## Voice chat between the members of a lobby, in the lobby and in the game.
##
## The voice of the local player is recorded by a VoiceSource and sent to the other
## members; theirs is played as it arrives. `LobbyConfig.voice_range` says where it
## comes out of:
## - EVERYONE: everyone hears everyone, at the same volume.
## - PROXIMITY: the voice of a player comes out of the VoiceEmitter3D of its character,
##   and fades with distance. Players without one (in the lobby) are heard by everyone.
##
## A player talks while it holds the `voice_talk` input action (PUSH_TO_TALK) or
## whenever it speaks (OPEN_MIC), as `activation` says.
##
## Reached through the lobby service: `Lobby.voice`, or `VoiceChat.find_for(node)`.
## This node receives RPCs: it must have the same name and path on every peer.

## A player started or stopped talking. Also emitted for the local player.
signal speaking_changed(peer_id: int, is_speaking: bool)
## Voice of another player, about to be played: samples from -1 to 1, one channel, at
## the sample rate of the source.
signal voice_received(peer_id: int, samples: PackedFloat32Array)
## `activation`, `is_microphone_muted` or a muted member changed.
signal settings_changed

## Input action held to talk in push-to-talk. Ignored when the project has none.
const TALK_ACTION: StringName = &"voice_talk"
## Largest packet sent or accepted, in bytes. Voice is sent without guarantee of
## delivery, and what does not fit in one network packet (about 1400 bytes) is lost
## much more often.
const MAX_PACKET_BYTES: int = 1200
## Most packets accepted from one player in a second.
const MAX_PACKETS_PER_SECOND: int = 120
## Time a player still counts as talking after its last packet, in seconds.
const SPEAKING_HOLD: float = 0.35
## Voice kept ahead of the playback, in seconds. More absorbs an irregular connection,
## and delays the voice by as much when packets arrive in bursts.
const BUFFER_SECONDS: float = 0.5

## How the local player talks.
var activation: LobbyTypes.VoiceActivation = LobbyTypes.VoiceActivation.PUSH_TO_TALK:
	set(value):
		activation = value
		settings_changed.emit()
## The local player is not recorded at all.
var is_microphone_muted: bool = false:
	set(value):
		is_microphone_muted = value
		settings_changed.emit()
## Talk in push-to-talk without the input action: for a button of the interface, or a
## gamepad handled by the game.
var is_talk_pressed: bool = false
## Audio bus of the voices heard by everyone. Emitters choose their own.
var bus: StringName = &"Master"

var source: VoiceSource

var _config: LobbyConfig
var _members: LobbyMemberSync
## Users the local player does not want to hear, by user id: kept when they reconnect.
var _muted_user_ids: Array[int] = []
## Where the voice of each peer is played when it has no emitter.
var _players: Dictionary[int, AudioStreamPlayer] = {}
var _emitters: Dictionary[int, AudioStreamPlayer3D] = {}
## When each peer was last heard (or the local player last recorded), in milliseconds.
var _heard_at: Dictionary[int, int] = {}
var _speaking_peers: Array[int] = []
## Packets received from each peer during the current second.
var _packet_counts: Dictionary[int, int] = {}
var _packet_second: int = 0

## Returns the voice chat a node belongs to, null when there is none.
static func find_for(node: Node) -> VoiceChat:
	var lobby: LobbyService = LobbyService.for_node(node)
	return lobby.voice if lobby != null else null

## Must be called once, before the node enters the tree. `voice_source` can be null:
## nobody is recorded nor heard then.
func setup(config: LobbyConfig, members: LobbyMemberSync, voice_source: VoiceSource) -> void:
	_config = config
	_members = members
	activation = config.voice_activation
	source = voice_source
	if source != null:
		source.name = "Source"
		add_child(source)
	_members.member_removed.connect(_on_member_removed)

## True when voices are sent and played at all.
func is_enabled() -> bool:
	return _config.voice_enabled and source != null

## True when the local player has a microphone that can be recorded.
func can_talk() -> bool:
	return is_enabled() and source.is_available()

func is_speaking(peer_id: int) -> bool:
	return _speaking_peers.has(peer_id)

## Stops or resumes playing the voice of a member, for the local player only.
func set_member_muted(member: LobbyMember, muted: bool) -> void:
	if muted == _muted_user_ids.has(member.user_id):
		return
	if muted:
		_muted_user_ids.append(member.user_id)
	else:
		_muted_user_ids.erase(member.user_id)
	settings_changed.emit()

func is_member_muted(member: LobbyMember) -> bool:
	return _muted_user_ids.has(member.user_id)

## Makes the voice of a peer come out of `emitter` in PROXIMITY range. VoiceEmitter3D
## calls it by itself.
func register_emitter(peer_id: int, emitter: AudioStreamPlayer3D) -> void:
	_emitters[peer_id] = emitter

func unregister_emitter(peer_id: int, emitter: AudioStreamPlayer3D) -> void:
	if _emitters.get(peer_id) == emitter:
		_emitters.erase(peer_id)

func _process(_delta: float) -> void:
	if source == null:
		return
	var local_member: LobbyMember = _members.local_member
	var is_recording: bool = local_member != null and _wants_to_talk()
	source.set_capturing(is_recording)
	if is_recording:
		for packet: PackedByteArray in source.read_packets():
			_send(packet, local_member.peer_id)
	_update_speaking()

# --- Talking -----------------------------------------------------------------------------

func _wants_to_talk() -> bool:
	if not can_talk() or is_microphone_muted or _members.members.size() < 2:
		return false
	if activation == LobbyTypes.VoiceActivation.OPEN_MIC:
		return true
	return is_talk_pressed or (InputMap.has_action(TALK_ACTION) and Input.is_action_pressed(TALK_ACTION))

func _send(packet: PackedByteArray, local_peer_id: int) -> void:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return
	_heard_at[local_peer_id] = Time.get_ticks_msec()
	for peer_id: int in _members.members:
		if peer_id != local_peer_id:
			_voice.rpc_id(peer_id, packet)

# --- Listening ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _voice(packet: PackedByteArray) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var member: LobbyMember = _members.get_member(peer_id)
	# Only from a member of the lobby, and no more than a voice needs.
	if member == null or not is_enabled() or packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return
	if not _count_packet(peer_id) or is_member_muted(member):
		return
	var samples: PackedFloat32Array = source.decode(packet)
	if samples.is_empty():
		return
	_heard_at[peer_id] = Time.get_ticks_msec()
	voice_received.emit(peer_id, samples)
	_play(peer_id, samples)

func _count_packet(peer_id: int) -> bool:
	var second: int = Time.get_ticks_msec() / 1000
	if second != _packet_second:
		_packet_second = second
		_packet_counts.clear()
	_packet_counts[peer_id] = _packet_counts.get(peer_id, 0) + 1
	return _packet_counts[peer_id] <= MAX_PACKETS_PER_SECOND

func _play(peer_id: int, samples: PackedFloat32Array) -> void:
	var playback: AudioStreamGeneratorPlayback = _playback_of(_output_of(peer_id))
	# Full when packets came in a burst: the oldest voice is the one worth keeping.
	if playback == null or playback.get_frames_available() < samples.size():
		return
	var frames: PackedVector2Array = PackedVector2Array()
	frames.resize(samples.size())
	for index: int in samples.size():
		frames[index] = Vector2(samples[index], samples[index])
	playback.push_buffer(frames)

## The node the voice of a peer comes out of: an AudioStreamPlayer3D on its character
## in PROXIMITY range, an AudioStreamPlayer heard by everyone otherwise.
func _output_of(peer_id: int) -> Node:
	if _config.voice_range == LobbyTypes.VoiceRange.PROXIMITY:
		var emitter: AudioStreamPlayer3D = _emitters.get(peer_id)
		if is_instance_valid(emitter) and emitter.is_inside_tree():
			return emitter
	if not _players.has(peer_id):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		_players[peer_id] = player
	return _players[peer_id]

## Makes an AudioStreamPlayer or an AudioStreamPlayer3D ready to receive voice.
func _playback_of(output: Node) -> AudioStreamGeneratorPlayback:
	var generator: AudioStreamGenerator = output.get(&"stream") as AudioStreamGenerator
	if generator == null or not is_equal_approx(generator.mix_rate, source.get_sample_rate()):
		generator = AudioStreamGenerator.new()
		generator.mix_rate = source.get_sample_rate()
		generator.buffer_length = BUFFER_SECONDS
		output.set(&"stream", generator)
	if output.get(&"playing") != true:
		output.call(&"play")
	return output.call(&"get_stream_playback") as AudioStreamGeneratorPlayback

# --- State -------------------------------------------------------------------------------

func _update_speaking() -> void:
	var now: int = Time.get_ticks_msec()
	for peer_id: int in _heard_at.keys():
		var is_heard: bool = now - _heard_at[peer_id] < SPEAKING_HOLD * 1000.0
		if is_heard == _speaking_peers.has(peer_id):
			continue
		if is_heard:
			_speaking_peers.append(peer_id)
		else:
			_speaking_peers.erase(peer_id)
			_heard_at.erase(peer_id)
		speaking_changed.emit(peer_id, is_heard)

func _on_member_removed(member: LobbyMember) -> void:
	var peer_id: int = member.peer_id
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_emitters.erase(peer_id)
	_heard_at.erase(peer_id)
	_packet_counts.erase(peer_id)
	if _speaking_peers.has(peer_id):
		_speaking_peers.erase(peer_id)
		speaking_changed.emit(peer_id, false)
