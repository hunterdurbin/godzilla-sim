class_name TurnTrackerModule
extends Node

## Turn/phase tracker concern for the game board: the phase + sub-phase label
## grid, the queued/animated tracker transitions, and the per-player auto
## setting toggles that live on those labels (clicking a phase/sub-phase
## label toggles its auto setting).
##
## Subscribes itself to TurnManager phase/turn signals on session_started for
## the tracker concern only — game_board.gd keeps its own handlers for the
## sync/broadcast/stats concerns. Binding happens inside start_host_session's
## emit, which runs BEFORE the board connects its own handlers, so
## current_sub_phase is always updated before the board's broadcast fires.
##
## Node references are captured once at _ready — the mobile layout may later
## reparent the TurnTracker container, which doesn't invalidate them.

const PHASE_TRANSITION_DELAY: float = 0.0

const SETTING_KEYS: Array[String] = [
	"auto_draw", "auto_phase_advance", "auto_discard_strategies",
	"auto_reset_rage", "auto_counter_check", "auto_advance",
	"confirm_main_phase_pass",
]

var _board: Node
var _session: GameSession

var current_sub_phase: int = 0

# Per-player auto settings (initialized from GameSettings, toggled
# independently). Read by the board's confirmation flow via a forwarding
# property.
var player_settings: Array[Dictionary] = []
var _setting_labels: Dictionary = {} # setting_name -> Array[Label]

# Tracker transition queue
var _tracker_queue: Array[Dictionary] = []
var _tracker_draining: bool = false
var _tracker_last_phase: int = -1
var _tracker_last_player: int = -1

# Label references [player_id][phase_index] (resolved at _ready)
var headers: Array = []
var _phases: Array = []
var _subs: Array = []
var _turn_label: Label
var _tracker_root: Control
var _collapsed: bool = false


func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node == null:
		push_error("[TurnTracker] No GameSession sibling — tracker will not bind.")
		return
	_session = session_node
	_session.session_started.connect(_bind_session)

	var t := _board.get_node("VBoxContainer/BoardArea/RightSpacer/TurnTracker")
	_tracker_root = t
	headers = [t.get_node("P1Header"), t.get_node("P2Header")]
	_turn_label = _board.get_node("VBoxContainer/BoardArea/RightSpacer/TurnLabelMargin/TurnLabel")
	_phases = []
	_subs = []
	for p in ["P1", "P2"]:
		_phases.append([
			t.get_node(p + "Start"), t.get_node(p + "Main"),
			t.get_node(p + "Counter"), t.get_node(p + "End"),
		])
		_subs.append([
			[t.get_node(p + "StartEffects"), t.get_node(p + "StartDraw"),
			 t.get_node(p + "StartDiscard"), t.get_node(p + "StartReset")],
			[t.get_node(p + "MainEffects"), t.get_node(p + "MainActions")],
			[t.get_node(p + "CounterEffects"), t.get_node(p + "CounterCheck")],
			[t.get_node(p + "EndEffects"), t.get_node(p + "EndAdvance"),
			 t.get_node(p + "EndRefill")],
		])


func _bind_session() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null:
		return # Client peer: tracker updates arrive via the state broadcast
	_connect_once(tm.phase_started, _on_phase_started)
	_connect_once(tm.sub_phase_changed, _on_sub_phase_changed)
	_connect_once(tm.turn_started, _on_turn_started)


func _connect_once(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	current_sub_phase = 0
	update_turn_tracker(_session.game_state.current_player_id, phase, 0)


func _on_sub_phase_changed(sub_index: int) -> void:
	current_sub_phase = sub_index
	update_turn_tracker(
		_session.game_state.current_player_id,
		_session.game_state.current_phase,
		sub_index)


func _on_turn_started(_player_id: int) -> void:
	current_sub_phase = 0


## Collapse the phase list to just the turn chip (the TurnLabel line) while
## a prompt panel occupies the right edge. No-op on mobile, where the whole
## tracker column is hidden by the mobile layout.
func set_collapsed(on: bool) -> void:
	if _board._is_mobile_layout:
		on = false
	if on == _collapsed:
		return
	_collapsed = on
	if _tracker_root:
		_tracker_root.visible = not on
	_refresh_turn_label()


## Update the TurnLabel line: plain turn number normally, a compact
## "Turn N · Phase" chip while collapsed (so the phase stays visible).
func _refresh_turn_label(phase_hint: int = -1) -> void:
	if _turn_label == null:
		return
	var gs: GameState = _session.turn_manager.game_state if _session.turn_manager else null
	var turn_num: int = gs.turn_number if gs else _session.client_turn_number
	if _collapsed:
		var phase_idx: int = phase_hint
		if phase_idx < 0:
			phase_idx = _tracker_last_phase if _tracker_last_phase >= 0 else (int(gs.current_phase) if gs else 0)
		var phase_name := CardEnums.phase_to_string(phase_idx as CardEnums.GamePhase)
		_turn_label.text = tr("STR_GB_TURN_CHIP_FMT").replace("{N}", str(turn_num)).replace("{PHASE}", phase_name)
	else:
		_turn_label.text = tr("STR_GB_TURN_FMT").replace("{N}", str(turn_num))


## Reset queue + indicator state for a rematch.
func reset_for_rematch() -> void:
	current_sub_phase = 0
	_tracker_queue.clear()
	_tracker_draining = false
	_tracker_last_phase = -1
	_tracker_last_player = -1
	apply_turn_tracker(0, CardEnums.GamePhase.START, 0)


func update_turn_tracker(player_id: int, phase: CardEnums.GamePhase, sub_phase: int = 0) -> void:
	var phase_int := int(phase)
	# Collapse: if last queued entry has same player+phase, just update its sub_phase
	if _tracker_queue.size() > 0:
		var last := _tracker_queue[_tracker_queue.size() - 1]
		if last.player_id == player_id and last.phase == phase_int:
			last.sub_phase = sub_phase
			return
	_tracker_queue.append({"player_id": player_id, "phase": phase_int, "sub_phase": sub_phase})
	if not _tracker_draining:
		_drain_tracker_queue()


func _drain_tracker_queue() -> void:
	_tracker_draining = true
	while _tracker_queue.size() > 0:
		var entry := _tracker_queue[0]
		_tracker_queue.remove_at(0)
		var phase_changed: bool = _tracker_last_phase >= 0 and (entry.phase != _tracker_last_phase or entry.player_id != _tracker_last_player)
		_tracker_last_phase = entry.phase
		_tracker_last_player = entry.player_id
		if phase_changed:
			await get_tree().create_timer(PHASE_TRANSITION_DELAY).timeout
		apply_turn_tracker(entry.player_id, entry.phase as CardEnums.GamePhase, entry.sub_phase)
	_tracker_draining = false


func apply_turn_tracker(player_id: int, phase: CardEnums.GamePhase, sub_phase: int = 0) -> void:
	var active_color := Color(1.0, 0.9, 0.3, 1.0) # Gold for active phase/sub
	var inactive_color := Color(0.4, 0.4, 0.5, 1.0) # Dim for inactive phases
	var inactive_sub_color := Color(0.35, 0.35, 0.4, 1.0) # Dimmer for inactive sub-phases
	var active_header_color := Color(1.0, 1.0, 1.0, 1.0) # White for active player
	var inactive_header_color := Color(0.6, 0.6, 0.7, 1.0) # Dim for inactive player
	# Update turn number label (chip form while collapsed)
	var gs: GameState = _session.turn_manager.game_state if _session.turn_manager else null
	var turn_num: int = gs.turn_number if gs else _session.client_turn_number
	_refresh_turn_label(int(phase))
	var phase_idx := int(phase)
	for pid in range(2):
		var first_marker := "* " if pid == _board._first_player_id else "  "
		headers[pid].text = first_marker + GameLog.player_name(pid)
		headers[pid].add_theme_color_override(
			"font_color", active_header_color if pid == player_id else inactive_header_color)
		for i in range(4):
			var is_active_phase := pid == player_id and i == phase_idx
			var label: Label = _phases[pid][i]
			label.add_theme_color_override("font_color", active_color if is_active_phase else inactive_color)
			var show_stop: bool = (not _board.is_multiplayer_game or pid == _board.local_player_id) and not is_setting_auto("auto_phase_advance", pid)
			var auto_indicator := "● " if show_stop else "  "
			label.text = ("► " if is_active_phase else "  ") + auto_indicator + CardEnums.phase_to_string(i as CardEnums.GamePhase)
			var subs: Array = _subs[pid][i]
			for si in range(subs.size()):
				var sub_label: Label = subs[si]
				var is_active_sub := is_active_phase and si == sub_phase
				sub_label.add_theme_color_override("font_color", active_color if is_active_sub else inactive_sub_color)

	# Update compact mobile phase indicator
	if _board._mobile_phase_label:
		var phase_name := CardEnums.phase_to_string(phase)
		var pname := GameLog.player_name(player_id)
		_board._mobile_phase_label.text = tr("STR_GB_TURN_HEADER_FMT").replace("{N}", str(turn_num)).replace("{PLAYER}", pname).replace("{PHASE}", phase_name)


# --- Per-player auto setting toggles (live on the tracker labels) ---

## Wire setting toggles onto the tracker labels. Called from the board's
## _ready after the multiplayer identity flags are set (the wiring skips the
## remote player's labels in multiplayer).
func setup_settings_toggles() -> void:
	# Initialize per-player settings from GameSettings defaults
	for pid in range(2):
		var d := {}
		for key in SETTING_KEYS:
			d[key] = GameSettings.get(key)
		player_settings.append(d)

	# Sub-phase label → setting mappings: [phase_idx, sub_idx, setting_name]
	var mappings: Array[Array] = [
		[0, 1, "auto_draw"], # Start > Draw Cards
		[0, 2, "auto_discard_strategies"], # Start > Discard Strategies
		[0, 3, "auto_reset_rage"], # Start > Reset Rage
		[1, 1, "confirm_main_phase_pass"], # Main > Player Actions
		[2, 1, "auto_counter_check"], # Counter > Counter Check
		[3, 1, "auto_advance"], # End > Advance
		[3, 2, "auto_draw"], # End > Refill Hand
	]

	for pid in range(2):
		# In multiplayer, only make the local player's labels clickable
		if _board.is_multiplayer_game and pid != _board.local_player_id:
			continue
		for m in mappings:
			_wire_setting_label(_subs[pid][m[0]][m[1]], m[2], pid)
		for i in range(4):
			_wire_setting_label(_phases[pid][i], "auto_phase_advance", pid)

	_update_all_setting_indicators()


func _wire_setting_label(label: Label, setting: String, pid: int) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.set_meta("setting", setting)
	label.set_meta("player_id", pid)
	label.set_meta("base_text", label.text)
	label.gui_input.connect(_on_setting_label_input.bind(label))
	if not _setting_labels.has(setting):
		_setting_labels[setting] = []
	_setting_labels[setting].append(label)


func _on_setting_label_input(event: InputEvent, label: Label) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var setting: String = label.get_meta("setting")
		var pid: int = label.get_meta("player_id")
		player_settings[pid][setting] = not player_settings[pid][setting]
		_update_all_setting_indicators()
		# Re-apply turn tracker so phase label indicators refresh immediately
		if _tracker_last_phase >= 0:
			apply_turn_tracker(_tracker_last_player, _tracker_last_phase as CardEnums.GamePhase, current_sub_phase)


func is_setting_auto(setting: String, pid: int) -> bool:
	# For most settings, true = auto. For confirm_main_phase_pass, true = manual.
	if player_settings.is_empty():
		return setting != "confirm_main_phase_pass"
	var value: bool = player_settings[pid].get(setting, false)
	if setting == "confirm_main_phase_pass":
		return not value
	return value


func _update_all_setting_indicators() -> void:
	for setting in _setting_labels:
		for label in _setting_labels[setting]:
			var pid: int = label.get_meta("player_id")
			if label in _phases[0] or label in _phases[1]:
				continue # Phase labels are updated in apply_turn_tracker
			var base: String = label.get_meta("base_text")
			# `base` is captured from .tscn (raw STR_* key). The auto branch can
			# assign it back as-is and let Godot auto-translate at render time.
			# The manual branch composes a new string ("● " + …) that's not a
			# known translation key, so we must resolve it ourselves first.
			if not is_setting_auto(setting, pid):
				var resolved := tr(base)
				var stripped := resolved.strip_edges(true, false)
				var indent_len := resolved.length() - stripped.length()
				label.text = resolved.left(maxi(indent_len - 2, 0)) + "● " + stripped
				label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			else:
				label.text = base
				label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
