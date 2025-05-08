extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var host_icon: TextureRect = $HostIcon

var player: NetworkPlayer

func _ready() -> void:
	if !player:
		queue_free()
		return
	name_label.text = player.name
	if !player.is_host:
		host_icon.hide()
