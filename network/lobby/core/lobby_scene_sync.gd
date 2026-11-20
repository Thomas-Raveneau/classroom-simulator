class_name LobbySceneSync
extends Node
## Loads a scene on every member of the lobby and tracks who has it loaded.
##
## The host orders the load and waits for every member before declaring the scene ready
## (the "barrier"): nothing has to be spawned for a player whose scene is not there yet.
## The list of ready peers is then kept up to date on everyone, which also handles
## players joining in progress.
##
## Before a game scene is left, every player first stops replicating it: an update still
## travelling to a player who already left the scene would be an error on its side.
##
## This node receives RPCs: it must have the same name and path on every peer.

## Maximum time the host waits for the players to stop replicating, in seconds.
const PAUSE_TIMEOUT: float = 1.0

## The local player starts loading `path`.
signal load_started(path: String, target_state: LobbyTypes.State)
## The local player could not load the scene, or the host did not load it in time.
signal load_failed
## The scene is loaded on every member: the local player enters `target_state`.
signal completed(target_state: LobbyTypes.State)
## A member has the scene loaded. Only emitted once the local player completed,
## and then once for every ready member (the local one included).
signal peer_ready(peer_id: int)
signal ready_peers_changed

## Scene ordered by the host, empty when no game scene is active.
var scene_path: String = ""
## Peers that have the scene loaded, known once the barrier opened.
var ready_peers: Array[int] = []

var _config: LobbyConfig
var _members: LobbyMemberSync
var _loader: LobbySceneLoader
## Identifies the current order. Only grows, so late answers and timers of a previous
## order are recognized and ignored.
var _load_id: int = 0
var _target_state: LobbyTypes.State = LobbyTypes.State.NONE
var _is_loading_locally: bool = false
var _is_completed: bool = false
## Ready peers already announced through `peer_ready`.
var _announced_peers: Array[int] = []
## Host: peers that reported the scene as loaded.
var _loaded_peers: Array[int] = []
## Host: peers the barrier waits for.
var _expected_peers: Array[int] = []
var _is_barrier_open: bool = false
## The game scene is about to be left: nothing is replicated anymore.
var _is_paused: bool = false
## Host: order waiting for every player to pause.
var _pending_path: String = ""
var _pending_target_state: LobbyTypes.State = LobbyTypes.State.NONE
var _pause_pending_peers: Array[int] = []

func setup(config: LobbyConfig, members: LobbyMemberSync, loader: LobbySceneLoader) -> void:
	_config = config
	_members = members
	_loader = loader
	_members.member_added.connect(_on_member_added)
	_members.member_removed.connect(_on_member_removed)
	_loader.changed.connect(_on_scene_changed)
	_loader.failed.connect(_on_scene_failed)

## True when what belongs to the game scene can be replicated to this peer.
func is_peer_ready(peer_id: int) -> bool:
	return not _is_paused and ready_peers.has(peer_id)

## Peers the game scene can be replicated to. Empty while the scene is being left.
func get_ready_peers() -> Array[int]:
	var empty: Array[int] = []
	return empty if _is_paused else ready_peers.duplicate()

## True from the moment the host ordered the game scene until it orders the lobby back.
func is_game_active() -> bool:
	return not scene_path.is_empty() and _target_state == LobbyTypes.State.IN_GAME

## Host only. Loads `path` on every member, who then enter `target_state`.
func order_load(path: String, target_state: LobbyTypes.State) -> void:
	if not _members.is_host():
		return
	_load_id += 1
	_pending_path = path
	_pending_target_state = target_state
	_pause_pending_peers.clear()
	if is_game_active():
		for peer_id: int in _members.members:
			if peer_id != multiplayer.get_unique_id():
				_pause_pending_peers.append(peer_id)
				_pause.rpc_id(peer_id, _load_id)
	if _pause_pending_peers.is_empty():
		_start_pending_load(_load_id)
	else:
		get_tree().create_timer(PAUSE_TIMEOUT).timeout.connect(_start_pending_load.bind(_load_id))

func _start_pending_load(load_id: int) -> void:
	if load_id != _load_id or _pending_path.is_empty() or not _members.is_host():
		return
	var path: String = _pending_path
	var target_state: LobbyTypes.State = _pending_target_state
	_pending_path = ""
	_pause_pending_peers.clear()
	_loaded_peers.clear()
	_is_barrier_open = false
	_expected_peers.assign(_members.members.keys())
	get_tree().create_timer(_config.load_timeout).timeout.connect(_on_load_timeout.bind(load_id))
	# The host leaves its current scene first: what it replicated is despawned on the
	# other players while they still have the scene it belongs to.
	_begin_load(path, load_id, target_state)
	await get_tree().process_frame
	if load_id != _load_id or not _members.is_host():
		return
	for peer_id: int in _expected_peers:
		if peer_id != multiplayer.get_unique_id() and _members.members.has(peer_id):
			_load.rpc_id(peer_id, path, load_id, target_state)

func reset() -> void:
	# Not reset to 0: see _load_id.
	_load_id += 1
	scene_path = ""
	_target_state = LobbyTypes.State.NONE
	_is_loading_locally = false
	_is_completed = false
	_is_barrier_open = false
	_is_paused = false
	_pending_path = ""
	_pause_pending_peers.clear()
	_loaded_peers.clear()
	_expected_peers.clear()
	_announced_peers.clear()
	if not ready_peers.is_empty():
		ready_peers.clear()
		ready_peers_changed.emit()

# --- Loading -----------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _pause(load_id: int) -> void:
	_is_paused = true
	ready_peers_changed.emit()
	_pause_done.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, load_id)

@rpc("any_peer", "call_remote", "reliable")
func _pause_done(load_id: int) -> void:
	if not _members.is_host() or load_id != _load_id:
		return
	_pause_pending_peers.erase(multiplayer.get_remote_sender_id())
	if _pause_pending_peers.is_empty():
		_start_pending_load(load_id)

@rpc("authority", "call_remote", "reliable")
func _load(path: String, load_id: int, target_state: LobbyTypes.State) -> void:
	_begin_load(path, load_id, target_state)

func _begin_load(path: String, load_id: int, target_state: LobbyTypes.State) -> void:
	_load_id = load_id
	scene_path = path
	_target_state = target_state
	_is_loading_locally = true
	_is_completed = false
	_is_paused = false
	_announced_peers.clear()
	_set_ready_peers([])
	load_started.emit(path, target_state)
	_loader.load_scene(path)

func _on_scene_changed(path: String) -> void:
	if not _is_loading_locally or path != scene_path:
		return
	_is_loading_locally = false
	if _members.is_host():
		_mark_loaded(multiplayer.get_unique_id())
	else:
		_loaded.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, _load_id)

func _on_scene_failed(path: String) -> void:
	if not _is_loading_locally or path != scene_path:
		return
	_is_loading_locally = false
	load_failed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _loaded(load_id: int) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if _members.is_host() and load_id == _load_id and _members.members.has(peer_id):
		_mark_loaded(peer_id)

# --- Host: barrier -----------------------------------------------------------------------

func _mark_loaded(peer_id: int) -> void:
	if not _loaded_peers.has(peer_id):
		_loaded_peers.append(peer_id)
	_evaluate()

func _evaluate() -> void:
	if scene_path.is_empty():
		return
	if not _is_barrier_open:
		for peer_id: int in _expected_peers:
			if _members.members.has(peer_id) and not _loaded_peers.has(peer_id):
				return
		_is_barrier_open = true
	var new_ready_peers: Array[int] = []
	for peer_id: int in _loaded_peers:
		if _members.members.has(peer_id):
			new_ready_peers.append(peer_id)
	# Applied on the host first: it starts replicating to a newly ready player before the
	# other players learn about it and start sending it their own state.
	_apply_ready_peers(new_ready_peers)
	for peer_id: int in _members.members:
		if peer_id != multiplayer.get_unique_id():
			_sync_ready_peers.rpc_id(peer_id, _load_id, new_ready_peers)

func _on_load_timeout(load_id: int) -> void:
	if load_id != _load_id or not _members.is_host() or scene_path.is_empty():
		return
	if not _loaded_peers.has(multiplayer.get_unique_id()):
		load_failed.emit()
		return
	for peer_id: int in _members.members.keys():
		if not _loaded_peers.has(peer_id):
			_members.dismiss(peer_id, LobbyTypes.Reason.LOAD_FAILED)

func _on_member_added(member: LobbyMember) -> void:
	# A player joining in progress loads the game scene too. The barrier does not wait
	# for it: it is announced as ready once loaded.
	if not _members.is_host() or member.is_host or not is_game_active():
		return
	if not _pending_path.is_empty():
		# The game scene is being left: the newcomer follows with everyone else.
		return
	var load_id: int = _load_id
	_load.rpc_id(member.peer_id, scene_path, load_id, _target_state)
	get_tree().create_timer(_config.load_timeout).timeout.connect(
		func() -> void:
			if load_id == _load_id and _members.is_host() and not _loaded_peers.has(member.peer_id):
				_members.dismiss(member.peer_id, LobbyTypes.Reason.LOAD_FAILED)
	)

func _on_member_removed(member: LobbyMember) -> void:
	_announced_peers.erase(member.peer_id)
	if _members.is_host():
		_loaded_peers.erase(member.peer_id)
		_expected_peers.erase(member.peer_id)
		_pause_pending_peers.erase(member.peer_id)
		if not _pending_path.is_empty():
			if _pause_pending_peers.is_empty():
				_start_pending_load(_load_id)
			return
		_evaluate()
	elif ready_peers.has(member.peer_id):
		var remaining_peers: Array[int] = ready_peers.duplicate()
		remaining_peers.erase(member.peer_id)
		_set_ready_peers(remaining_peers)

# --- Ready peers -------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _sync_ready_peers(load_id: int, peers: Array) -> void:
	if load_id != _load_id:
		return
	var new_ready_peers: Array[int] = []
	for peer_id: Variant in peers:
		if peer_id is int:
			new_ready_peers.append(peer_id)
	_apply_ready_peers(new_ready_peers)

func _apply_ready_peers(new_ready_peers: Array[int]) -> void:
	_set_ready_peers(new_ready_peers)
	if not _is_completed:
		if not ready_peers.has(multiplayer.get_unique_id()):
			return
		_is_completed = true
		var target_state: LobbyTypes.State = _target_state
		if target_state != LobbyTypes.State.IN_GAME:
			# Back in the lobby: no game scene is active anymore.
			scene_path = ""
		completed.emit(target_state)
	for peer_id: int in ready_peers.duplicate():
		if not _announced_peers.has(peer_id):
			_announced_peers.append(peer_id)
			peer_ready.emit(peer_id)

func _set_ready_peers(new_ready_peers: Array[int]) -> void:
	if ready_peers == new_ready_peers:
		return
	ready_peers = new_ready_peers
	ready_peers_changed.emit()
