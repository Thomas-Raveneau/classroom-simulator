@abstract class_name VoiceSource
extends Node
## Where the voice of the local player comes from, and how it is packed for the network.
## VoiceChat only knows this class: one implementation per way of capturing and
## compressing (Steam, the microphone of Godot...). Every player of a lobby must use the
## same one, which is the case when it is chosen from the backend.

## True when the local player can be recorded. Voices received are played either way.
@abstract func is_available() -> bool

## Sample rate of what `decode()` returns, in hertz.
@abstract func get_sample_rate() -> int

## Starts or stops recording the local player.
@abstract func set_capturing(capturing: bool) -> void

## What was recorded since the last call, in packets ready to be sent. Empty while the
## player is silent.
@abstract func read_packets() -> Array[PackedByteArray]

## Turns a packet received from another player into samples (one channel, from -1 to 1)
## at `get_sample_rate()`. Empty when the packet is not valid: it comes from a player.
@abstract func decode(packet: PackedByteArray) -> PackedFloat32Array

## 16-bit little-endian PCM to samples from -1 to 1.
static func pcm16_to_samples(bytes: PackedByteArray) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(bytes.size() >> 1)
	for index: int in samples.size():
		samples[index] = bytes.decode_s16(index * 2) / 32768.0
	return samples

## Samples from -1 to 1 to 16-bit little-endian PCM.
static func samples_to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index: int in samples.size():
		bytes.encode_s16(index * 2, roundi(clampf(samples[index], -1.0, 1.0) * 32767.0))
	return bytes
