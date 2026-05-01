extends Label

@export var player_id: int = 0
@export var format_string: String = "Discard: %d"

var _bound_player: PlayerState = null


func _ready() -> void:
	_try_bind()


func _try_bind() -> void:
	var session := BoardModule.find_session(self)
	if session == null:
		return
	var seat := BoardModule.find_seat(self)
	if seat:
		player_id = seat.get_player_id()
	if session.is_running() or not session.client_players.is_empty():
		_bind(session)
	else:
		session.session_started.connect(func(): _bind(session), CONNECT_ONE_SHOT)


func _bind(session: GameSession) -> void:
	var p := session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	_bound_player = p
	p.discard_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _bound_player:
		text = format_string % _bound_player.discard_pile.size()
