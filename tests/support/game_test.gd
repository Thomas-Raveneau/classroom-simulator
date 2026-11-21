class_name LobbyGameTest
extends GutTest
## Base of the tests that need several players in a running game: each player has its
## own lobby service and its own copy of LobbyTestGameScene, over a real ENet connection.

const GAME_SCENE: String = "res://game.tscn"
const LOBBY_SCENE: String = "res://lobby.tscn"
const WAIT: float = 3.0

var config: LobbyConfig
var port: int
var peers: Array[LobbyTestPeer]
## Bad connection given to the players added from now on. A perfect one when null.
var conditions: NetworkConditions

func before_each() -> void:
	config = LobbyConfig.new()
	config.join_timeout = 2.0
	config.load_timeout = 5.0
	config.dismiss_grace = 0.3
	config.game_scene = GAME_SCENE
	config.lobby_scene = LOBBY_SCENE
	config.allow_join_in_progress = true
	port = LobbyTestPeer.pick_port()
	peers = []
	conditions = null

func after_each() -> void:
	for test_peer: LobbyTestPeer in peers:
		test_peer.shutdown()
	peers.clear()

func add_peer() -> LobbyTestPeer:
	var test_peer: LobbyTestPeer = LobbyTestPeer.create(self, config, port, conditions)
	test_peer.loader.scene_factory = func(path: String) -> Node:
		return LobbyTestGameScene.new() if path == GAME_SCENE else Node.new()
	peers.append(test_peer)
	return test_peer

func add_host() -> LobbyTestPeer:
	var host: LobbyTestPeer = add_peer()
	host.service.create()
	await wait_for_signal(host.service.created, LobbyTestPeer.patience(WAIT))
	return host

## Adds a player and waits until its attempt to join ends, successfully or not.
func add_client() -> LobbyTestPeer:
	var client: LobbyTestPeer = add_peer()
	client.service.join(0)
	await wait_until(func() -> bool: return client.service.state != LobbyTypes.State.JOINING, LobbyTestPeer.patience(WAIT))
	return client

## Starts the game and waits until every player is in it.
func start_game(host: LobbyTestPeer) -> void:
	host.service.start_game()
	for test_peer: LobbyTestPeer in peers:
		await until(func() -> bool: return test_peer.service.state == LobbyTypes.State.IN_GAME, "player is in game")

func scene_of(test_peer: LobbyTestPeer) -> LobbyTestGameScene:
	return test_peer.loader.current_scene as LobbyTestGameScene

func until(condition: Callable, text: String) -> void:
	await wait_until(condition, LobbyTestPeer.patience(WAIT))
	assert_true(condition.call(), text)

## Ends the connection of a client as a network failure would: neither side said it was
## leaving, the host just finds the member gone.
func cut_connection(host: LobbyTestPeer, client: LobbyTestPeer) -> void:
	host.service._member_sync.drop(client.service.local_member.peer_id)
	await until(func() -> bool: return client.service.state == LobbyTypes.State.NONE, "client lost the connection")
