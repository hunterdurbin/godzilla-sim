class_name BoundLabel
extends Label

## Base class for player-bound HUD labels (RageDisplay, ThreatDisplay,
## DeckCountLabel, DiscardCountLabel, etc.). Handles the full
## auto-binding dance — session lookup, seat resolution, signal
## subscription, host-vs-client timing, seat-role swap rebinding,
## clean teardown — so subclasses only override `_refresh`.
##
## Designer sees the Bindings group in the inspector:
##   - session_path: optional NodePath; if unset, BoardModule.find_session
##     walks up the tree to locate the GameSession.
##   - player_id: explicit player to display; overridden by an ancestor
##     SeatContainer when present.
##
## Subclass:
##   extends BoundLabel
##   @export var format_string := "Rage: %d"
##   func _refresh(_session: GameSession, player: PlayerState) -> void:
##       text = format_string % player.rage

@export_group("Bindings")
## Optional explicit GameSession path. If unset, the label walks up
## the tree to find one via BoardModule.find_session().
@export var session_path: NodePath
## Which player to display. Overridden by an ancestor SeatContainer.
@export var player_id: int = 0

const _SIGNALS_NO_ARG: Array[StringName] = [
	&"hand_changed", &"zones_changed", &"monster_changed",
	&"strategy_zones_changed", &"deck_changed", &"discard_changed",
]
const _SIGNALS_ONE_ARG: Array[StringName] = [
	&"rage_changed",
]

var _session: GameSession = null
var _bound_player: PlayerState = null
var _bound_seat: SeatContainer = null
var _unbound_callable: Callable = Callable()


func _ready() -> void:
	_try_bind()


func _exit_tree() -> void:
	_disconnect_all()


# --- Override in subclass ---

## Update visual state. Called once on initial bind, then on every
## PlayerState mutation signal, and again whenever the seat's role
## flips (rebind to a different player).
func _refresh(_session: GameSession, _player: PlayerState) -> void:
	pass


# --- Binding plumbing ---

func _try_bind() -> void:
	# Resolve session: explicit @export wins, else tree-walk.
	if not session_path.is_empty():
		_session = get_node_or_null(session_path) as GameSession
	if _session == null:
		_session = BoardModule.find_session(self)
	if _session == null:
		return
	# Resolve seat-driven player_id when an ancestor SeatContainer exists.
	var seat := BoardModule.find_seat(self)
	if seat:
		_bound_seat = seat
		player_id = seat.get_player_id()
		if not seat.role_changed.is_connected(_on_seat_role_changed):
			seat.role_changed.connect(_on_seat_role_changed)
	if _session.is_running() or not _session.client_players.is_empty():
		_bind_player()
	else:
		_session.session_started.connect(_bind_player, CONNECT_ONE_SHOT)


func _bind_player() -> void:
	var p := _session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	_disconnect_player()
	_bound_player = p
	_unbound_callable = _on_signal_fired.unbind(1)
	for sig in _SIGNALS_NO_ARG:
		p.connect(sig, _on_signal_fired)
	for sig in _SIGNALS_ONE_ARG:
		p.connect(sig, _unbound_callable)
	_on_signal_fired()


func _on_signal_fired() -> void:
	if _bound_player and _session:
		_refresh(_session, _bound_player)


func _on_seat_role_changed(new_pid: int) -> void:
	player_id = new_pid
	_bind_player()


func _disconnect_player() -> void:
	if _bound_player == null:
		return
	for sig in _SIGNALS_NO_ARG:
		if _bound_player.is_connected(sig, _on_signal_fired):
			_bound_player.disconnect(sig, _on_signal_fired)
	if _unbound_callable.is_valid():
		for sig in _SIGNALS_ONE_ARG:
			if _bound_player.is_connected(sig, _unbound_callable):
				_bound_player.disconnect(sig, _unbound_callable)
	_bound_player = null


func _disconnect_all() -> void:
	_disconnect_player()
	if _bound_seat and _bound_seat.role_changed.is_connected(_on_seat_role_changed):
		_bound_seat.role_changed.disconnect(_on_seat_role_changed)
