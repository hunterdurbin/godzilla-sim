extends Label

@export var format_string: String = "Phase: %s"

var _session: GameSession = null


func _ready() -> void:
	_try_bind()


func _try_bind() -> void:
	_session = BoardModule.find_session(self)
	if _session == null:
		return
	if _session.is_running():
		_bind()
	else:
		_session.session_started.connect(_bind, CONNECT_ONE_SHOT)


func _bind() -> void:
	if _session == null or _session.turn_manager == null:
		return
	_session.turn_manager.phase_started.connect(_on_phase_started)


func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	text = format_string % CardEnums.GamePhase.keys()[phase]
