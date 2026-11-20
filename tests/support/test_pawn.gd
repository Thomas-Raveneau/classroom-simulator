class_name LobbyTestPawn
extends Node
## Replicated object owned by a player: `value` is synchronized by a synchronizer under
## the authority of that player. It has no ReplicationGate of its own: the NetworkSpawner
## that creates it adds one.

var value: int = 0

func _init() -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	var replication: SceneReplicationConfig = SceneReplicationConfig.new()
	replication.add_property(^".:value")
	replication.property_set_replication_mode(^".:value", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = replication
	add_child(synchronizer)
