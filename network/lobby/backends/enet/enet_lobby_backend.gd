class_name ENetLobbyBackend
extends LobbyBackend
## Local backend to test without Steam: the "lobby" is an ENet server on this machine.
## Launch several instances of the game with `--lobby-backend=enet`, create a lobby in
## one and join it from the others.
##
## It has no friends, no invites and no real lobby list; identities are not verified.
## Optional command line argument: `--lobby-name=<player name>`.

const ADDRESS: String = "127.0.0.1"
const NAME_ARGUMENT: String = "--lobby-name="
## Time a connection stays open after `leave()`, in seconds: what was sent just before
## (a goodbye, a closing notice) must be received before the disconnection, or the
## other side drops it.
const CLOSE_DELAY: float = 0.2

## Port to host on / connect to. Defaults to `LobbyConfig.enet_port`.
var port: int = 0

var _peer: ENetMultiplayerPeer
## Connections left and about to close.
var _closing_peers: Array[ENetMultiplayerPeer] = []
var _identity: Dictionary = {}

func setup(_config: LobbyConfig) -> void:
	super(_config)
	if port == 0:
		port = config.enet_port
	# Unverifiable but stable for the session, which is enough for the ban list.
	var user_id: int = randi_range(1, 1 << 30)
	_identity = { "user_id": user_id, "name": _read_name_argument("Player %d" % (user_id % 10000)) }

func is_available() -> bool:
	return true

func get_backend_name() -> String:
	return "enet"

func create(_visibility: LobbyTypes.Visibility) -> void:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if peer.create_server(port, config.max_players) != OK:
		_emit_deferred(lobby_create_failed, LobbyTypes.Reason.BACKEND_ERROR)
		return
	_peer = peer
	_emit_deferred(lobby_created, port)

## The lobby id is the port of the server, 0 for the default one.
func join(lobby_id: int) -> void:
	leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if peer.create_client(ADDRESS, lobby_id if lobby_id > 0 else port) != OK:
		_emit_deferred(lobby_join_failed, LobbyTypes.Reason.CONNECTION_FAILED)
		return
	_peer = peer
	_emit_deferred(lobby_joined, lobby_id if lobby_id > 0 else port)

func leave() -> void:
	# A connection still closing would keep the port of a new server busy.
	_close_pending_peers()
	if _peer == null:
		return
	var peer: ENetMultiplayerPeer = _peer
	_peer = null
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		peer.close()
		return
	peer.host.flush()
	_closing_peers.append(peer)
	get_tree().create_timer(CLOSE_DELAY).timeout.connect(_close_pending_peers)

func _close_pending_peers() -> void:
	for peer: ENetMultiplayerPeer in _closing_peers:
		peer.close()
	_closing_peers.clear()

func get_peer() -> MultiplayerPeer:
	return _peer

func get_local_identity() -> Dictionary:
	return _identity

func resolve_identity(_peer_id: int, claim: Dictionary) -> Dictionary:
	var user_id: Variant = claim.get("user_id")
	var user_name: Variant = claim.get("name")
	if user_id is not int or user_name is not String:
		return {}
	return { "user_id": user_id, "name": user_name }

## There is no discovery: always offers the local server, whether it runs or not.
func request_lobby_list() -> void:
	var info: LobbyInfo = LobbyInfo.new(port, "Local game (port %d)" % port)
	info.max_members = config.max_players
	var lobbies: Array[LobbyInfo] = [info]
	_emit_deferred(lobby_list_received, lobbies)

func _read_name_argument(default_name: String) -> String:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with(NAME_ARGUMENT):
			return argument.trim_prefix(NAME_ARGUMENT)
	return default_name
