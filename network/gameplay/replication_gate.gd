class_name ReplicationGate
extends MultiplayerSynchronizer
## Holds back the replication of an object until the receiving player has the game scene
## loaded. Add one as a direct child of every replicated object of a game scene, spawned
## by a MultiplayerSpawner or not: nothing else is needed.
##
## Why: Godot replicates to a player as soon as it is connected, even when it is still
## in the lobby or loading. An object received too early is lost, and the updates of its
## synchronizers never reach that player afterwards. This matters most for players
## joining in progress, but also at game start when players load at different speeds.
##
## How: the gate stays under the authority of the host, which decides who receives the
## spawn, and applies the same rule to the other synchronizers of the object, whoever
## owns them.

var _lobby: LobbyService
var _gated_synchronizers: Array[MultiplayerSynchronizer] = []

func _init() -> void:
	# A synchronizer without configuration is ignored by the engine.
	if replication_config == null:
		replication_config = SceneReplicationConfig.new()

func _enter_tree() -> void:
	# The authority of the object is usually given to a player, recursively: take the
	# gate back. Doing it here (not in _ready) is what the engine expects for spawns.
	if get_multiplayer_authority() != MultiplayerPeer.TARGET_PEER_SERVER:
		set_multiplayer_authority(MultiplayerPeer.TARGET_PEER_SERVER)
	_lobby = LobbyService.for_node(self)
	if _lobby == null:
		return
	var root: Node = get_node_or_null(root_path)
	if root == null:
		return
	for node: Node in root.find_children("*", "MultiplayerSynchronizer", true, false):
		var synchronizer: MultiplayerSynchronizer = node as MultiplayerSynchronizer
		synchronizer.add_visibility_filter(_is_peer_ready)
		_gated_synchronizers.append(synchronizer)
	_lobby.scene_ready_peers_changed.connect(_update_visibility)
	# The engine started replicating to every connected player when the synchronizers
	# entered the tree, before the filter existed: apply it now, not at the next frame.
	_update_visibility()

func _exit_tree() -> void:
	if _lobby == null:
		return
	_lobby.scene_ready_peers_changed.disconnect(_update_visibility)
	for synchronizer: MultiplayerSynchronizer in _gated_synchronizers:
		if is_instance_valid(synchronizer):
			synchronizer.remove_visibility_filter(_is_peer_ready)
	_gated_synchronizers.clear()
	_lobby = null

func _is_peer_ready(peer_id: int) -> bool:
	return _lobby == null or _lobby.is_peer_scene_ready(peer_id)

func _update_visibility() -> void:
	# The gate first: the object must be spawned before its synchronizers send anything.
	update_visibility()
	for synchronizer: MultiplayerSynchronizer in _gated_synchronizers:
		if synchronizer != self and is_instance_valid(synchronizer) and synchronizer.is_inside_tree():
			synchronizer.update_visibility()
