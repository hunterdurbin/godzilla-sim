class_name SessionBoundLabel
extends Label

## Base class for HUD labels bound to session-level state (turn number,
## phase, current-player banner, etc.) rather than a single PlayerState.
## Handles session lookup + host-vs-client bind timing so subclasses
## only override `_bind(session)` to wire signals.
##
## For player-bound labels (rage, deck count, ...), use BoundLabel
## instead — it adds player_id resolution + SeatContainer support.
##
## Subclass:
##   extends SessionBoundLabel
##   @export var format_string := "Turn: %d"
##
##   func _bind(session: GameSession) -> void:
##       session.turn_manager.turn_started.connect(_on_turn_started)
##       _refresh()
##
##   func _on_turn_started(_pid: int) -> void: _refresh()
##
##   func _refresh() -> void:
##       if _session and _session.game_state:
##           text = format_string % _session.game_state.turn_number

@export_group("Bindings")
## Optional explicit GameSession path. If unset, the label walks up
## the tree to find one via BoardModule.find_session().
@export var session_path: NodePath

var _session: GameSession = null


func _ready() -> void:
	_try_bind()


# --- Override in subclass ---

## Wire signals from session.turn_manager / session.effect_handler /
## etc. and call your own `_refresh()` here. Called once when the
## session is running (host: immediately; client: on session_started).
func _bind(_session: GameSession) -> void:
	pass


# --- Binding plumbing ---

func _try_bind() -> void:
	if not session_path.is_empty():
		_session = get_node_or_null(session_path) as GameSession
	if _session == null:
		_session = BoardModule.find_session(self)
	if _session == null:
		return
	if _session.is_running() or not _session.client_players.is_empty():
		_bind(_session)
	else:
		_session.session_started.connect(_on_session_started, CONNECT_ONE_SHOT)


func _on_session_started() -> void:
	if _session:
		_bind(_session)
