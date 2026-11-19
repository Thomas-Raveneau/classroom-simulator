class_name FakeSceneLoader
extends LobbySceneLoader
## Scene loader that loads no file. By default a scene is "shown" on the next frame;
## with `manual` the test decides when with `complete()` or `fail()`.
## With a `scene_factory`, the scene it builds is shown as a sibling named "Scene".

var manual: bool = false
## Every path asked, in order.
var requested_paths: Array[String] = []
## Path being "loaded", empty when idle.
var pending_path: String = ""
## Last scene "shown".
var current_path: String = ""
## Optional `func(path: String) -> Node` building the scene to show.
var scene_factory: Callable
var current_scene: Node

func load_scene(path: String, _confirm: Signal = Signal(), _timeout: float = 0.0) -> void:
	requested_paths.append(path)
	pending_path = path
	# Like the real loader, the current scene is left as soon as a load starts.
	if current_scene != null:
		current_scene.free()
		current_scene = null
	if not manual:
		complete.call_deferred()

func cancel() -> void:
	pending_path = ""

func complete() -> void:
	if pending_path.is_empty():
		return
	current_path = pending_path
	pending_path = ""
	if scene_factory.is_valid():
		current_scene = scene_factory.call(current_path)
		current_scene.name = "Scene"
		get_parent().add_child(current_scene)
	changed.emit(current_path)

func fail() -> void:
	if pending_path.is_empty():
		return
	var path: String = pending_path
	pending_path = ""
	failed.emit(path)
