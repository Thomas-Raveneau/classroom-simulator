class_name MultiplayerManager

var lobby: MultiplayerLobby
var network: MultiplayerNetwork

func _ready() -> void:
	lobby = MultiplayerLobby.new()
	network = MultiplayerNetwork.new()

func start_game() -> void:
	pass
