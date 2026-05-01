extends Label

## Drop-in threat-level display. Threat = base + rage*5000 + modifiers
## (per the rules engine). Auto-binds to the player's rage_changed and
## refreshes whenever any modifier-relevant state changes.

@export var player_id: int = 0
@export var format_string: String = "Threat: %d"

var _bound_player: PlayerState = null
var _session: GameSession = null


func _ready() -> void:
	_try_bind()


func _try_bind() -> void:
	_session = BoardModule.find_session(self)
	if _session == null:
		return
	var seat := BoardModule.find_seat(self)
	if seat:
		player_id = seat.get_player_id()
		if not seat.role_changed.is_connected(_on_seat_role_changed):
			seat.role_changed.connect(_on_seat_role_changed)
	if _session.is_running() or not _session.client_players.is_empty():
		_bind(_session)
	else:
		_session.session_started.connect(func(): _bind(_session), CONNECT_ONE_SHOT)


func _on_seat_role_changed(new_player_id: int) -> void:
	player_id = new_player_id
	if _session:
		_bind(_session)


func _bind(session: GameSession) -> void:
	var p := session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	# Disconnect previous bindings (rebind path for seat swap).
	if _bound_player:
		if _bound_player.rage_changed.is_connected(_on_rage_changed):
			_bound_player.rage_changed.disconnect(_on_rage_changed)
		if _bound_player.zones_changed.is_connected(_refresh):
			_bound_player.zones_changed.disconnect(_refresh)
		if _bound_player.strategy_zones_changed.is_connected(_refresh):
			_bound_player.strategy_zones_changed.disconnect(_refresh)
	_bound_player = p
	p.rage_changed.connect(_on_rage_changed)
	p.zones_changed.connect(_refresh)
	p.strategy_zones_changed.connect(_refresh)
	_refresh()


func _on_rage_changed(_new_rage: int) -> void:
	_refresh()


func _refresh() -> void:
	if _bound_player == null:
		return
	var base_threat: int = _bound_player.current_monster.get("threat", 0) if not _bound_player.current_monster.is_empty() else 0
	var threat := base_threat + _bound_player.rage * 5000
	if _session and _session.is_running() and _session.effect_handler:
		threat += _session.effect_handler.get_threat_level_modifier(player_id)
	elif _session and player_id < _session.client_threat_modifiers.size():
		threat += int(_session.client_threat_modifiers[player_id])
	text = format_string % threat
