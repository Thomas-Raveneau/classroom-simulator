class_name TestPawn
extends Node
## Replicated object owned by a player: `value` is synchronized by a synchronizer under
## the authority of that player, and a LobbySpawnGate holds everything back until the
## receiver has the scene.

var value: int = 0

func _init() -> void:
	var gate: LobbySpawnGate = LobbySpawnGate.new()
	gate.name = "Gate"
	add_child(gate)
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	var replication: SceneReplicationConfig = SceneReplicationConfig.new()
	replication.add_property(^".:value")
	replication.property_set_replication_mode(^".:value", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = replication
	add_child(synchronizer)
