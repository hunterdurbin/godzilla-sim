extends SessionBoundLabel

@export var format_string: String = "Turn: %d"


func _bind(session: GameSession) -> void:
	if session.turn_manager:
		session.turn_manager.turn_started.connect(_on_turn_started)
	_refresh()


func _on_turn_started(_player_id: int) -> void:
	_refresh()


func _refresh() -> void:
	if _session and _session.game_state:
		text = format_string % _session.game_state.turn_number
