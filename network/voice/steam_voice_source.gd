extends VoiceSource
## Voice recorded and compressed by Steam, from the microphone chosen in the Steam
## settings of the player. Steam only sends data while the player talks.
##
## Loaded by path for the Steam backend only: it needs the GodotSteam extension, and
## Steam to be started (the Steam backend does it).

## Rate the voices are decompressed at, in hertz. The same on every player, whatever
## rate Steam prefers on each machine.
const SAMPLE_RATE: int = 24000
## Room for one decompressed packet, in bytes: one second of voice.
const DECOMPRESSED_BYTES: int = SAMPLE_RATE * 2

var _is_capturing: bool = false

func is_available() -> bool:
	return Steam.isSteamRunning() and Steam.loggedOn()

func get_sample_rate() -> int:
	return SAMPLE_RATE

func set_capturing(capturing: bool) -> void:
	if capturing == _is_capturing or not is_available():
		return
	_is_capturing = capturing
	if capturing:
		Steam.startVoiceRecording()
	else:
		Steam.stopVoiceRecording()

func read_packets() -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	if not _is_capturing:
		return packets
	var available: Dictionary = Steam.getAvailableVoice()
	var size: Variant = available.get("size")
	if available.get("result") != Steam.VOICE_RESULT_OK or size is not int or size <= 0:
		return packets
	var voice: Dictionary = Steam.getVoice(size)
	var written: Variant = voice.get("size")
	var buffer: Variant = voice.get("buffer")
	if voice.get("result") == Steam.VOICE_RESULT_OK and written is int and written > 0 and buffer is PackedByteArray:
		var packet: PackedByteArray = buffer
		packet.resize(mini(written, packet.size()))
		packets.append(packet)
	return packets

func decode(packet: PackedByteArray) -> PackedFloat32Array:
	var voice: Dictionary = Steam.decompressVoice(packet, SAMPLE_RATE, DECOMPRESSED_BYTES)
	var size: Variant = voice.get("size")
	var pcm: Variant = voice.get("uncompressed")
	if voice.get("result") != Steam.VOICE_RESULT_OK or size is not int or size <= 0 or pcm is not PackedByteArray:
		return PackedFloat32Array()
	var bytes: PackedByteArray = pcm
	bytes.resize(mini(size, bytes.size()) & ~1)
	return pcm16_to_samples(bytes)

func _exit_tree() -> void:
	set_capturing(false)
