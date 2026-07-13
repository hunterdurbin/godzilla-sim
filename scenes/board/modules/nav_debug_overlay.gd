@tool
class_name NavDebugOverlay
extends Control
## Visualizes the controller-navigation graph over the board so editing
## BoardNavGraph is never blind.
##
## RUNTIME (debug builds only): press F3 to toggle. Paints the LIVE graph
## from GamepadBoardNav.debug_graph()/debug_state() — every node's rect
## color-coded (green = cursor, blue = valid, red = jailed out by the active
## prompt, gray = hidden/disabled), directional arrows to each edge's first
## candidate, and a corner HUD with the nav state. Pure paint: full-rect,
## MOUSE_FILTER_IGNORE, never a focus context, not in the overlay-suspend
## set — the cursor keeps working while it is up.
##
## EDITOR: check `editor_preview` in the inspector with GameBoard.tscn open
## to render the STATIC graph (playmat + UI tables; the hand/tracker/choice
## rows are runtime-only and drawn as a note). `preview_layout` flips
## between the desktop and mobile edge sets.

const COLOR_CURRENT := Color(0.35, 1.0, 0.55, 0.95)
const COLOR_VALID := Color(0.35, 0.65, 1.0, 0.85)
const COLOR_JAILED := Color(1.0, 0.35, 0.35, 0.85)
const COLOR_HIDDEN := Color(0.6, 0.6, 0.6, 0.5)
const COLOR_EDGE := Color(1.0, 0.9, 0.3, 0.55)
const COLOR_EDGE_ALT := Color(1.0, 0.9, 0.3, 0.2)
const COLOR_HUD_BG := Color(0.05, 0.05, 0.08, 0.8)
const REFRESH_SEC := 0.25
const ARROW_HEAD := 7.0

## Editor-only: render the static graph over the open scene.
@export var editor_preview := false:
	set(value):
		editor_preview = value
		queue_redraw()
## Editor-only: which layout's edge set to preview.
@export_enum("desktop", "mobile") var preview_layout := "desktop":
	set(value):
		preview_layout = value
		queue_redraw()

var _nav: Node = null
var _refresh_timer: Timer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Engine.is_editor_hint():
		return
	visible = false
	_nav = get_parent().get_node_or_null("GamepadBoardNav")
	if _nav:
		_nav.nav_state_changed.connect(queue_redraw)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SEC
	_refresh_timer.timeout.connect(queue_redraw)
	add_child(_refresh_timer)


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible
		if visible:
			_refresh_timer.start()
			queue_redraw()
		else:
			_refresh_timer.stop()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if Engine.is_editor_hint():
		if editor_preview:
			_draw_editor_graph()
		return
	if _nav == null:
		return
	_draw_runtime_graph()


# --- Runtime rendering (live nav state) ---

func _draw_runtime_graph() -> void:
	var graph: Dictionary = _nav.debug_graph()
	var state: Dictionary = _nav.debug_state()
	var current: String = state.get("element", "")
	var to_local := get_global_transform().affine_inverse()

	for id: String in graph:
		var node: Dictionary = graph[id]
		var rect: Rect2 = node["rect"]
		if rect.size == Vector2.ZERO:
			continue
		var local := Rect2(to_local * rect.position, rect.size)
		for dir: String in ["up", "right", "down", "left"]:
			var targets: Array = (node["edges"] as Dictionary).get(dir, [])
			for t in range(targets.size()):
				var target: Dictionary = graph.get(targets[t], {})
				var target_rect: Rect2 = target.get("rect", Rect2())
				if target_rect.size == Vector2.ZERO:
					continue
				var target_local := Rect2(to_local * target_rect.position, target_rect.size)
				_draw_arrow(_edge_anchor(local, dir), target_local.get_center(),
					COLOR_EDGE if t == 0 else COLOR_EDGE_ALT)
		var color := COLOR_HIDDEN
		if id == current:
			color = COLOR_CURRENT
		elif node["jailed_out"] and node["usable"]:
			color = COLOR_JAILED
		elif node["usable"]:
			color = COLOR_VALID
		draw_rect(local, color, false, 2.0)
		_draw_label(id, local.position + Vector2(2, -3), color)

	_draw_hud([
		"element: %s" % state.get("element", ""),
		"mode:    %s" % state.get("mode", ""),
		"ctx:     %s" % str(state.get("ctx", [])),
		"bumper:  %s" % str(state.get("bumper_return", {})),
		"pending_hand_return: %s" % state.get("pending_hand_return", false),
		"active:  %s" % state.get("active", false),
		"F3 hides",
	])


# --- Editor rendering (static tables over the open scene) ---

func _draw_editor_graph() -> void:
	var graph := BoardNavGraph.build({
		"mobile": preview_layout == "mobile",
		"hand_count": 0,
		"tracker_count": 0,
		"choice_count": 0,
	})
	var to_local := get_global_transform().affine_inverse()
	for id: String in graph:
		var rect := _editor_rect(id)
		if rect.size == Vector2.ZERO:
			continue
		var local := Rect2(to_local * rect.position, rect.size)
		for dir: String in ["up", "right", "down", "left"]:
			var targets: Array = (graph[id] as Dictionary).get(dir, [])
			for t in range(targets.size()):
				var target_rect := _editor_rect(targets[t])
				if target_rect.size == Vector2.ZERO:
					continue
				var target_local := Rect2(to_local * target_rect.position, target_rect.size)
				_draw_arrow(_edge_anchor(local, dir), target_local.get_center(),
					COLOR_EDGE if t == 0 else COLOR_EDGE_ALT)
		draw_rect(local, COLOR_VALID, false, 2.0)
		_draw_label(id, local.position + Vector2(2, -3), COLOR_VALID)
	_draw_hud([
		"BoardNavGraph static preview (%s)" % preview_layout,
		"hand_<i> / opp_hand_<i> / trk_<i> / choice_<i> rows are runtime-only (F3 in a debug build)",
		"edit tables in board_nav_graph.gd",
	])


## Editor-side id -> rect via scene node names (no autoloads, no
## player_board.gd runtime arrays — the seat boards are Player1Board =
## bottom, Player2Board = top exactly as GameBoard.tscn lays them out).
func _editor_rect(id: String) -> Rect2:
	var node := _editor_node(id)
	return node.get_global_rect() if node else Rect2()


func _editor_node(id: String) -> Control:
	var board := get_parent()
	if id.begins_with("top_") or id.begins_with("bot_"):
		var seat: Node = board.get_node_or_null(
			"VBoxContainer/BoardArea/BoardColumn/" +
			("Player1Board" if id.begins_with("bot_") else "Player2Board"))
		if seat == null:
			return null
		var rest := id.substr(4)
		if rest.begins_with("z"):
			return seat.find_child("Zone" + rest.substr(1), true, false) as Control
		if rest.begins_with("strategy_"):
			return seat.find_child("Strategy%d" % (rest.substr(9).to_int() + 1), true, false) as Control
		match rest:
			"rage": return seat.find_child("RageDisplay", true, false) as Control
			"deck": return seat.find_child("DeckInfo", true, false) as Control
			"monster_deck": return seat.find_child("MonsterInfo", true, false) as Control
			"discard": return seat.find_child("DiscardInfo", true, false) as Control
		return null
	const UI_PATHS := {
		"ap_cancel": "ActionPanel/Row0/Cancel",
		"ap_confirm": "ActionPanel/Row0/Confirm",
		"ap_play_battle": "ActionPanel/Row1/PlayBattle",
		"ap_play_strategy": "ActionPanel/Row1/PlayStrategy",
		"ap_gain_rage": "ActionPanel/Row1/GainRage",
		"ap_play_monster": "ActionPanel/Row2/PlayMonster",
		"ap_invade": "ActionPanel/Row2/Invade",
		"ap_end_main": "ActionPanel/Row2/EndMain",
		"ap_hand_toggle": "HandButtonStack/HandToggleButton",
		"ap_sort_hand": "HandButtonStack/SortHandButton",
		"ap_opp_hand_toggle": "OpponentHandButtonStack/OpponentHandToggleButton",
		"ap_opp_sort_hand": "OpponentHandButtonStack/OpponentSortHandButton",
		"sys_bug_report": "BugReportButton",
		"sys_concede": "ConcedeButton",
		"sys_main_menu": "MainMenuButton",
		"sys_sound": "SoundToggleButton",
		"sys_music": "MusicToggleButton",
		"sys_export_log": "ExportLogButton",
		"log_panel": "LogPanel",
	}
	if UI_PATHS.has(id):
		return board.get_node_or_null(UI_PATHS[id]) as Control
	return null


# --- Shared drawing helpers ---

func _edge_anchor(rect: Rect2, dir: String) -> Vector2:
	match dir:
		"up": return Vector2(rect.get_center().x, rect.position.y)
		"down": return Vector2(rect.get_center().x, rect.end.y)
		"left": return Vector2(rect.position.x, rect.get_center().y)
		"right": return Vector2(rect.end.x, rect.get_center().y)
	return rect.get_center()


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 1.5)
	var back := (from - to).normalized() * ARROW_HEAD
	draw_line(to, to + back.rotated(0.5), color, 1.5)
	draw_line(to, to + back.rotated(-0.5), color, 1.5)


func _draw_label(text: String, at: Vector2, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_hud(lines: Array) -> void:
	var line_h := 16.0
	var width := 0.0
	var font := ThemeDB.fallback_font
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var origin := Vector2(8, 8)
	draw_rect(Rect2(origin, Vector2(width + 16.0, lines.size() * line_h + 12.0)), COLOR_HUD_BG)
	for i in range(lines.size()):
		draw_string(font, origin + Vector2(8, line_h * (i + 1)), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
