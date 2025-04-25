extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var host_icon: TextureRect = $HostIcon

var member: SteamUser
var host_only_nodes: Array[Node] = []

func _ready() -> void:
	if !member:
		queue_free()
	name_label.text = member.name
	if !member.is_host:
		host_icon.hide()
	if !SteamManager.user.is_host:
		return
	for host_only_node in host_only_nodes:
		host_only_node.hide()
