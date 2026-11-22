class_name NetworkConditions
extends Resource
## Debug tool: how bad the simulated connection of a player is (see SimulatedNetworkPeer).
## Everything at zero is a perfect connection.
##
## Give one to `LobbyService.network_conditions` before creating or joining a lobby, or
## launch the game with `--net-latency=150 --net-jitter=30 --net-loss=5`. The values can
## be changed while connected.

const LATENCY_ARGUMENT: String = "--net-latency="
const JITTER_ARGUMENT: String = "--net-jitter="
const LOSS_ARGUMENT: String = "--net-loss="

## Added to the ping of this player, in milliseconds: half on what it sends, half on
## what it receives.
@export_range(0, 2000, 1, "suffix:ms") var latency_ms: int = 0
## Random extra delay of each packet, up to this value in milliseconds. Packets that do
## not have to arrive in order then overtake each other.
@export_range(0, 1000, 1, "suffix:ms") var jitter_ms: int = 0
## Share of the packets lost in each direction. What is sent as unreliable (positions,
## pings) is dropped; what is sent as reliable arrives late instead, as after a resend.
@export_range(0.0, 100.0, 0.1, "suffix:%") var loss_percent: float = 0.0

func is_active() -> bool:
	return latency_ms > 0 or jitter_ms > 0 or loss_percent > 0.0

func describe() -> String:
	return "%d ms latency, %d ms jitter, %s %% loss" % [latency_ms, jitter_ms, String.num(loss_percent, 1)]

## The conditions asked on a command line, null when it asks for none.
static func from_arguments(arguments: PackedStringArray) -> NetworkConditions:
	var conditions: NetworkConditions = NetworkConditions.new()
	for argument: String in arguments:
		if argument.begins_with(LATENCY_ARGUMENT):
			conditions.latency_ms = maxi(argument.trim_prefix(LATENCY_ARGUMENT).to_int(), 0)
		elif argument.begins_with(JITTER_ARGUMENT):
			conditions.jitter_ms = maxi(argument.trim_prefix(JITTER_ARGUMENT).to_int(), 0)
		elif argument.begins_with(LOSS_ARGUMENT):
			conditions.loss_percent = clampf(argument.trim_prefix(LOSS_ARGUMENT).to_float(), 0.0, 100.0)
	return conditions if conditions.is_active() else null
