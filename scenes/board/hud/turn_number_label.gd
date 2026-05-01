extends Label

@export var format_string: String = "Turn: %d"

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
	_session.turn_manager.turn_started.connect(_on_turn_started)
	_refresh()


func _on_turn_started(_player_id: int) -> void:
	_refresh()


func _refresh() -> void:
	if _session and _session.game_state:
		text = format_string % _session.game_state.turn_number
