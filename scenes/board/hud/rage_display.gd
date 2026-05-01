extends Label

## Drop-in rage display. Auto-binds to the given player's rage_changed
## signal. Set `player_id` and (optionally) `format_string` in the inspector.

@export var player_id: int = 0
@export var format_string: String = "Rage: %d"

var _bound_player: PlayerState = null


func _ready() -> void:
	_try_bind()


func _try_bind() -> void:
	var session := BoardModule.find_session(self)
	if session == null:
		return
	# If under a SeatContainer, the seat dictates which player we display —
	# overrides the local @export. Designer drops the module under
	# LocalSeat / OpponentSeat and never touches player_id by hand.
	var seat := BoardModule.find_seat(self)
	if seat:
		player_id = seat.get_player_id()
		if not seat.role_changed.is_connected(_on_seat_role_changed):
			seat.role_changed.connect(_on_seat_role_changed)
	if session.is_running() or not session.client_players.is_empty():
		_bind(session)
	else:
		session.session_started.connect(func(): _bind(session), CONNECT_ONE_SHOT)


func _on_seat_role_changed(new_player_id: int) -> void:
	player_id = new_player_id
	var session := BoardModule.find_session(self)
	if session:
		_bind(session)


func _bind(session: GameSession) -> void:
	var p := session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	if _bound_player and _bound_player.rage_changed.is_connected(_on_rage_changed):
		_bound_player.rage_changed.disconnect(_on_rage_changed)
	_bound_player = p
	p.rage_changed.connect(_on_rage_changed)
	_refresh()


func _on_rage_changed(_new_rage: int) -> void:
	_refresh()


func _refresh() -> void:
	if _bound_player:
		text = format_string % _bound_player.rage
