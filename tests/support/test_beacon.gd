class_name LobbyTestBeacon
extends Node
## Replicated object that is part of the game scene itself (not spawned), owned by the
## host. Its ReplicationGate is declared by hand, as it would be in a scene file.

var value: int = 0

func _init() -> void:
	var gate: ReplicationGate = ReplicationGate.new()
	gate.name = "ReplicationGate"
	add_child(gate)
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	var replication: SceneReplicationConfig = SceneReplicationConfig.new()
	replication.add_property(^".:value")
	replication.property_set_replication_mode(^".:value", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = replication
	add_child(synchronizer)
