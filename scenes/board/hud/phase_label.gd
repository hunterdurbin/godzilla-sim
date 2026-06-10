extends SessionBoundLabel

@export var format_string: String = "Phase: %s"


func _bind(session: GameSession) -> void:
	if session.turn_manager:
		session.turn_manager.phase_started.connect(_on_phase_started)


func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	text = format_string % CardEnums.GamePhase.keys()[phase]
