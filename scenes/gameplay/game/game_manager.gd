class_name GameManager
extends Node

@export var player_scene: PackedScene
@export var players_container: Node3D

func _ready() -> void:
	if !players_container:
		push_error("players_container not set")
		return
	if !player_scene:
		push_error("player_scene not set")
		return
	spawn_players()

func spawn_players() -> void:
	for player in NetworkManager.lobby.players:
		var player_instance: Player = player_scene.instantiate()
		players_container.add_child(player_instance)
