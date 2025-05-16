class_name SpawnPoint
extends Node3D

@onready var spawn_timer: Timer = $SpawnTimer

@export var is_spawnable: bool = true
var spawn_delay_seconds: int = 2

func _ready() -> void:
	spawn_timer.one_shot = true
	spawn_timer.autostart = false
	spawn_timer.timeout.connect(_on_spawn_delay_timeout)

func use() -> void:
	is_spawnable = false
	spawn_timer.start(spawn_delay_seconds)

func _on_spawn_delay_timeout() -> void:
	is_spawnable = true
