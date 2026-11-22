class_name SpawnPoint
extends Node3D
## A place where a player can appear. It stays busy for a moment after being used, so two
## players do not appear inside each other.

signal freed_up

@export var cooldown_seconds: float = 2.0

var is_free: bool = true

@onready var _timer: Timer = $SpawnTimer

func _ready() -> void:
	_timer.one_shot = true
	_timer.timeout.connect(_on_cooldown_finished)

func use() -> void:
	is_free = false
	_timer.start(cooldown_seconds)

func _on_cooldown_finished() -> void:
	is_free = true
	freed_up.emit()
