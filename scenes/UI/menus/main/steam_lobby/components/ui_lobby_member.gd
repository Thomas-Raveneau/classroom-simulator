extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var host_icon: TextureRect = $HostIcon

var member: SteamUser

func _ready() -> void:
	if !member:
		queue_free()
	name_label.text = member.name
	if !member.is_host:
		host_icon.hide()
