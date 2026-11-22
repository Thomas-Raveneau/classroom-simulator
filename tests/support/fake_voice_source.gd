class_name FakeVoiceSource
extends VoiceSource
## Voice source of the tests: "records" the packets a test gives it, and decodes a
## packet into one sample per byte.

var available: bool = true
var is_capturing: bool = false
## What the player "says": sent at the next frame, while recording.
var spoken: Array[PackedByteArray] = []

func is_available() -> bool:
	return available

func get_sample_rate() -> int:
	return 16000

func set_capturing(capturing: bool) -> void:
	is_capturing = capturing

func read_packets() -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = spoken
	spoken = []
	return packets

func decode(packet: PackedByteArray) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for byte: int in packet:
		samples.append(byte / 255.0)
	return samples
