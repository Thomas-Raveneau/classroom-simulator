extends CanvasLayer
## In-game display and controls: the phase of the match and its timer, the scores with
## the latency of each player and who is talking, and the buttons to go back to the
## lobby or leave.
## Leaving as the host closes the lobby for everyone.

const PHASE_TEXTS: Dictionary[StringName, String] = {
	MatchState.PHASE_WAITING: "Waiting for players",
	MatchState.PHASE_COUNTDOWN: "Get ready",
	MatchState.PHASE_PLAYING: "Collect the coins",
	MatchState.PHASE_RESULTS: "Results",
}
const ABSENT_COLOR: Color = Color(1, 1, 1, 0.4)
const SPEAKING_COLOR: Color = Color(0.5, 0.8, 1)

@export var match_state: MatchState

@onready var _back_button: Button = %BackButton
@onready var _phase_label: Label = %PhaseLabel
@onready var _time_label: Label = %TimeLabel
@onready var _scores: VBoxContainer = %Scores

func _ready() -> void:
	_back_button.visible = Lobby.is_host()
	match_state.phase_changed.connect(_refresh_phase.unbind(1))
	match_state.score_changed.connect(_refresh_scores.unbind(2))
	Lobby.member_joined.connect(_refresh_scores.unbind(1))
	Lobby.member_left.connect(_refresh_scores.unbind(1))
	Lobby.member_updated.connect(_refresh_scores.unbind(2))
	Lobby.voice.speaking_changed.connect(_refresh_scores.unbind(2))
	_refresh_phase()
	_refresh_scores()

func _process(_delta: float) -> void:
	_time_label.visible = match_state.time_left > 0.0
	_time_label.text = str(ceili(match_state.time_left))

func _refresh_phase() -> void:
	_phase_label.text = PHASE_TEXTS.get(match_state.phase, String(match_state.phase))
	_refresh_scores()

## One line per player of the match, best score first. Players who left stay listed,
## dimmed: they keep their score and may come back.
func _refresh_scores() -> void:
	for child: Node in _scores.get_children():
		child.queue_free()
	for user_id: int in match_state.get_ranking():
		var member: LobbyMember = _find_member(user_id)
		var line: Label = Label.new()
		line.text = "%s   %d" % [match_state.get_player_name(user_id), match_state.get_score(user_id)]
		if member == null:
			line.modulate = ABSENT_COLOR
		else:
			if member.ping > 0:
				line.text += "   %d ms" % member.ping
			if Lobby.voice.is_speaking(member.peer_id):
				line.modulate = SPEAKING_COLOR
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_scores.add_child(line)

func _find_member(user_id: int) -> LobbyMember:
	for member: LobbyMember in Lobby.get_members():
		if member.user_id == user_id:
			return member
	return null

func _on_back_button_pressed() -> void:
	Lobby.return_to_lobby()

func _on_leave_button_pressed() -> void:
	Lobby.leave()
