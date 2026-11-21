class_name MicrophoneVoiceSource
extends VoiceSource
## Voice from the microphone of Godot, sent uncompressed (16-bit, 16 kHz, one channel:
## about 32 kB per second and per listener while talking). Meant to test voice chat locally without
## Steam; a released game should use a source that compresses.
##
## Needs the project setting "Audio > Driver > Enable Input", off by default because
## the system then asks every player for the microphone as soon as the game starts.

const INPUT_SETTING: String = "audio/driver/enable_input"
const CAPTURE_BUS: StringName = &"VoiceCapture"
const SAMPLE_RATE: int = 16000
## Samples per packet: 30 milliseconds, 960 bytes (see VoiceChat.MAX_PACKET_BYTES).
const PACKET_SAMPLES: int = 480
## Time the microphone keeps sending after the voice went under the threshold, in
## seconds, so the end of words is not cut.
const SILENCE_HOLD: float = 0.4

## Loudness (root mean square, from 0 to 1) under which a packet is silence.
@export_range(0.0, 0.2, 0.001) var silence_threshold: float = 0.01

var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
## Recorded and not sent yet: less than a packet.
var _pending: PackedFloat32Array = PackedFloat32Array()
## Where the next sample to keep is in the audio received, in input frames.
var _read_position: float = 0.0
var _silent_for: float = INF

func is_available() -> bool:
	return ProjectSettings.get_setting(INPUT_SETTING, false) == true

func get_sample_rate() -> int:
	return SAMPLE_RATE

func set_capturing(capturing: bool) -> void:
	if not is_available() or capturing == (_microphone != null and _microphone.playing):
		return
	if capturing:
		_start()
	else:
		_microphone.stop()
		_capture.clear_buffer()
		_pending.clear()
		_silent_for = INF

func read_packets() -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	if _microphone == null or not _microphone.playing:
		return packets
	var frames: PackedVector2Array = _capture.get_buffer(_capture.get_frames_available())
	_pending.append_array(_to_voice_rate(frames, AudioServer.get_mix_rate()))
	while _pending.size() >= PACKET_SAMPLES:
		var samples: PackedFloat32Array = _pending.slice(0, PACKET_SAMPLES)
		_pending = _pending.slice(PACKET_SAMPLES)
		if loudness(samples) >= silence_threshold:
			_silent_for = 0.0
		else:
			_silent_for += float(PACKET_SAMPLES) / SAMPLE_RATE
		if _silent_for < SILENCE_HOLD:
			packets.append(samples_to_pcm16(samples))
	return packets

func decode(packet: PackedByteArray) -> PackedFloat32Array:
	if packet.size() & 1 == 1:
		return PackedFloat32Array()
	return pcm16_to_samples(packet)

## Root mean square of samples, from 0 to 1.
static func loudness(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum: float = 0.0
	for sample: float in samples:
		sum += sample * sample
	return sqrt(sum / samples.size())

## Stereo audio at `from_rate` to one channel at SAMPLE_RATE, keeping one sample out
## of `from_rate / SAMPLE_RATE`.
func _to_voice_rate(frames: PackedVector2Array, from_rate: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var step: float = from_rate / SAMPLE_RATE
	while _read_position < frames.size():
		var frame: Vector2 = frames[int(_read_position)]
		samples.append((frame.x + frame.y) * 0.5)
		_read_position += step
	_read_position -= frames.size()
	return samples

func _start() -> void:
	if _microphone == null:
		# Its own bus, muted: the microphone is recorded, not played on the speakers.
		var bus: int = AudioServer.get_bus_index(CAPTURE_BUS)
		if bus == -1:
			bus = AudioServer.bus_count
			AudioServer.add_bus(bus)
			AudioServer.set_bus_name(bus, CAPTURE_BUS)
			AudioServer.set_bus_mute(bus, true)
			AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
		_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
		_microphone = AudioStreamPlayer.new()
		_microphone.stream = AudioStreamMicrophone.new()
		_microphone.bus = CAPTURE_BUS
		add_child(_microphone)
	_capture.clear_buffer()
	_read_position = 0.0
	_microphone.play()
