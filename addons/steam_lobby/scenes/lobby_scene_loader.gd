class_name LobbySceneLoader
extends Node
## What the lobby kit needs from a scene loader. The kit ships `TreeSceneLoader`
## (the `SceneLoader` autoload); tests use their own implementation.

## The scene at `path` is now the running scene.
signal changed(path: String)
## The scene at `path` could not be loaded (missing file, timeout...).
signal failed(path: String)

## Loads then shows the scene at `path`, replacing any load still in progress.
## With a `confirm` signal, the scene is only shown once that signal was emitted.
## With a positive `timeout` (seconds), `failed` is emitted when the scene is not shown in time.
func load_scene(_path: String, _confirm: Signal = Signal(), _timeout: float = 0.0) -> void:
	pass

## Gives up the load in progress, if any. Emits nothing.
func cancel() -> void:
	pass
