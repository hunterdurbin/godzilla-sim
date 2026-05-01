extends VBoxContainer

## Drop-in compact turn tracker. Shows the 4 phases (Start / Main /
## Counter / End) for both players with the active phase highlighted.
## Auto-binds to session phase signals.
##
## This is a SIMPLER reimplementation than the one currently inlined in
## game_board.gd (which also shows sub-phases and per-row settings
## toggles). Designer can extend if more detail is needed.

const _PHASE_NAMES := ["Start", "Main", "Counter", "End"]
const _ACTIVE_COLOR := Color(1.0, 0.9, 0.3)
const _INACTIVE_COLOR := Color(0.4, 0.4, 0.5)

var _session: GameSession = null
var _player_rows: Array[VBoxContainer] = []
var _phase_labels: Array[Array] = [[], []]
var _current_player: int = -1
var _current_phase: int = -1


func _ready() -> void:
	_build_layout()
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
	_session.turn_manager.turn_started.connect(_on_turn_started)


func _build_layout() -> void:
	add_theme_constant_override("separation", 8)
	for pid in range(2):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		add_child(col)
		_player_rows.append(col)

		var header := Label.new()
		header.text = "Player %d" % (pid + 1)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_color_override("font_color", _INACTIVE_COLOR)
		col.add_child(header)

		var phase_labels: Array = []
		for phase_name in _PHASE_NAMES:
			var lbl := Label.new()
			lbl.text = "  %s Phase" % phase_name
			lbl.add_theme_color_override("font_color", _INACTIVE_COLOR)
			lbl.add_theme_font_size_override("font_size", 11)
			col.add_child(lbl)
			phase_labels.append(lbl)
		_phase_labels[pid] = phase_labels


func _on_turn_started(player_id: int) -> void:
	_current_player = player_id
	_refresh()


func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	_current_phase = int(phase)
	_refresh()


func _refresh() -> void:
	for pid in range(2):
		for phase_idx in range(_PHASE_NAMES.size()):
			var lbl: Label = _phase_labels[pid][phase_idx]
			var is_active := pid == _current_player and phase_idx == _current_phase
			lbl.add_theme_color_override("font_color", _ACTIVE_COLOR if is_active else _INACTIVE_COLOR)
