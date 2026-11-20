class_name LobbyTestPeer
extends Node
## One player of an in-process multiplayer test: a branch of the tree with its own
## multiplayer API, hosting a complete lobby service over a real ENet connection.
## RPC paths are relative to the branch, so they match between the players of a test.

var service: LobbyService
var backend: ENetLobbyBackend
var loader: FakeLobbySceneLoader

## Adds a new player under `parent`. Every player of a test must share `port`.
static func create(parent: Node, config: LobbyConfig, port: int) -> LobbyTestPeer:
	var test_peer: LobbyTestPeer = LobbyTestPeer.new()
	parent.add_child(test_peer)
	# The multiplayer API must be in place before the nodes using it enter the tree.
	parent.get_tree().set_multiplayer(SceneMultiplayer.new(), test_peer.get_path())
	test_peer.loader = FakeLobbySceneLoader.new()
	test_peer.add_child(test_peer.loader)
	test_peer.backend = ENetLobbyBackend.new()
	test_peer.backend.port = port
	test_peer.service = LobbyService.new()
	test_peer.service.name = "Lobby"
	test_peer.service.setup(config, test_peer.backend, test_peer.loader)
	test_peer.add_child(test_peer.service)
	return test_peer

## Leaves the lobby and removes the player from the test.
func shutdown() -> void:
	service.leave()
	# Freed while the branch still has its multiplayer API, which the replication nodes
	# need to unregister from.
	for child: Node in get_children():
		child.free()
	get_tree().set_multiplayer(null, get_path())
	queue_free()

## A port unlikely to be in use, different for every test.
static func pick_port() -> int:
	return randi_range(20000, 60000)
