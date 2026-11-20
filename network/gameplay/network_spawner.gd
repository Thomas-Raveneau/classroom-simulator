class_name NetworkSpawner
extends MultiplayerSpawner
## Makes objects appear and disappear on every player: characters, pickups, projectiles.
##
## The host decides: it calls `spawn_scene()`, and frees the returned node to remove it
## everywhere. Each object gets a ReplicationGate, so it only reaches the players whose
## game scene is loaded (see ReplicationGate).
##
## Set `spawn_path` to the node that will hold the objects, as for any MultiplayerSpawner.

## Scenes this spawner may create. Every player must have the same list in the same order,
## which is the case when it is set in the scene file.
@export var scenes: Array[PackedScene] = []

func _init() -> void:
	spawn_function = _create_object

func _ready() -> void:
	var lobby: LobbyService = LobbyService.for_node(self)
	if lobby != null and multiplayer.is_server():
		lobby.member_left.connect(_on_member_left)

## What a player owned does not outlive it: nobody would control it anymore.
func _on_member_left(member: LobbyMember) -> void:
	for node: Node in get_node(spawn_path).get_children():
		if node.get_multiplayer_authority() == member.peer_id:
			node.queue_free()

## Host only. Spawns `scene` on every player and returns the node created on the host.
## - `properties`: values set on the node before it enters the tree (e.g. `position`).
##   Only use types that can be sent over the network, no objects.
## - `owner_peer_id`: the peer given authority over the object. The host by default.
## - `node_name`: optional name of the node, the same on every player.
func spawn_scene(
	scene: PackedScene, properties: Dictionary = {}, owner_peer_id: int = MultiplayerPeer.TARGET_PEER_SERVER,
	node_name: String = ""
) -> Node:
	if not multiplayer.is_server():
		push_error("NetworkSpawner: only the host can spawn.")
		return null
	var scene_index: int = scenes.find(scene)
	if scene_index == -1:
		push_error("NetworkSpawner: %s is not in the `scenes` of %s." % [scene.resource_path, get_path()])
		return null
	return spawn({
		"scene": scene_index, "properties": properties, "owner": owner_peer_id, "name": node_name,
	})

## Runs on every player: builds the node the host asked for.
func _create_object(data: Dictionary) -> Node:
	var scene_index: int = data["scene"]
	var properties: Dictionary = data["properties"]
	var node_name: String = data["name"]
	var owner_peer_id: int = data["owner"]
	var node: Node = scenes[scene_index].instantiate()
	if not node_name.is_empty():
		node.name = node_name
	for property: Variant in properties:
		if property is String or property is StringName:
			node.set(property, properties[property])
	node.set_multiplayer_authority(owner_peer_id)
	if not _has_gate(node):
		var gate: ReplicationGate = ReplicationGate.new()
		gate.name = "ReplicationGate"
		node.add_child(gate)
	return node

func _has_gate(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is ReplicationGate:
			return true
	return false
