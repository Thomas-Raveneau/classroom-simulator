class_name LobbyTestPawn
extends Node
## Replicated object owned by a player: `value` is synchronized by a synchronizer under
## the authority of that player, and its animations by a NetworkAnimation. It has no
## ReplicationGate of its own: the NetworkSpawner that creates it adds one.

var value: int = 0
## What the animations of the pawn move.
var animated: float = 0.0
var animation_player: AnimationPlayer
var animation: NetworkAnimation

func _init() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(&"idle", _make_animation(Animation.LOOP_LINEAR))
	library.add_animation(&"wave", _make_animation(Animation.LOOP_NONE))
	animation_player.add_animation_library(&"", library)
	add_child(animation_player)
	animation = NetworkAnimation.new()
	animation.name = "Animation"
	animation.animation_player = animation_player
	add_child(animation)
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	var replication: SceneReplicationConfig = SceneReplicationConfig.new()
	replication.add_property(^".:value")
	replication.property_set_replication_mode(^".:value", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	replication.add_property(^"Animation:sync_state")
	replication.property_set_replication_mode(^"Animation:sync_state", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = replication
	add_child(synchronizer)

func _make_animation(loop_mode: Animation.LoopMode) -> Animation:
	var new_animation: Animation = Animation.new()
	new_animation.length = 0.3
	new_animation.loop_mode = loop_mode
	var track: int = new_animation.add_track(Animation.TYPE_VALUE)
	new_animation.track_set_path(track, ^".:animated")
	new_animation.track_insert_key(track, 0.0, 0.0)
	new_animation.track_insert_key(track, 0.3, 1.0)
	return new_animation
