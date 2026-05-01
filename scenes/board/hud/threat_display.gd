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
	if _session.is_running() or not _session.client_players.is_empty():
		_bind(_session)
	else:
		_session.session_started.connect(func(): _bind(_session), CONNECT_ONE_SHOT)


func _bind(session: GameSession) -> void:
	var p := session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	_bound_player = p
	# Threat depends on rage + modifiers (which can change on many events).
	# Subscribe to the most relevant signals; refresh on any of them.
	p.rage_changed.connect(_refresh.unbind(1))
	p.zones_changed.connect(_refresh)
	p.strategy_zones_changed.connect(_refresh)
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
