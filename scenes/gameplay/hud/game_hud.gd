extends CanvasLayer
## In-game controls: the host can bring everyone back to the lobby, and anyone
## can leave. Leaving as the host closes the lobby for everyone.

@onready var _back_button: Button = %BackButton

func _ready() -> void:
	_back_button.visible = Lobby.is_host()

func _on_back_button_pressed() -> void:
	Lobby.return_to_lobby()

func _on_leave_button_pressed() -> void:
	Lobby.leave()
