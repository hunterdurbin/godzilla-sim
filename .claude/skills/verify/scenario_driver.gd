extends Node
## Scenario driver for scenario.sh: starts a real solo GameBoard, then runs a
## scenario script's `run(v)` against it. The scenario is compiled from its
## source at runtime, so it can live anywhere (committed under scenarios/,
## or a throwaway in the scratchpad).
##
## User args: --scenario=<path to .gd> --shots=<dir>. Prints "[Scenario] ..."
## lines; "[Scenario] DONE" is the completion marker.
##
## What a scenario gets (`v` = this node):
##   v.board  GameBoard        v.tm  TurnManager     v.gs  GameState
##   v.h      EffectHandler    v.ed  BoardEditor (stage state: mint_card,
##            set_strategy, add_to_hand / add_to_deck / add_to_discard,
##            add_to_zone, set_rage, ... — emits the change signals itself)
##   await v.wait(sec)         v.shot(label)        v.close_overlays()
##   v.log_tail(n) -> lines    v.note(msg)          (prints "[Scenario] msg")

var board: Node
var tm: TurnManager
var gs: GameState
var h: EffectHandler
var ed: BoardEditor
var shots_dir: String = ""
var _scenario_path: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
	board = load("res://scenes/board/GameBoard.tscn").instantiate()
	add_child(board)
	_run()


func _run() -> void:
	await wait(2.0)
	tm = board.turn_manager
	gs = tm.game_state
	h = tm.effect_handler
	ed = BoardEditor.new(tm)
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(_scenario_path)
	if script.source_code.is_empty() or script.reload() != OK:
		print("[Scenario] FAIL cannot load scenario %s" % _scenario_path)
		get_tree().quit()
		return
	var scenario: Object = script.new()
	if not scenario.has_method("run"):
		print("[Scenario] FAIL scenario has no run(v)")
		get_tree().quit()
		return
	note("turn=%d current=%d phase=%s" % [gs.turn_number, gs.current_player_id, gs.current_phase])
	await scenario.call("run", self)
	note("DONE")
	get_tree().quit()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func note(msg: String) -> void:
	print("[Scenario] " + msg)


func shot(label: String) -> void:
	if shots_dir.is_empty():
		return
	var path := shots_dir.path_join(label + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	note("shot " + path)


func close_overlays() -> void:
	for b: Button in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and String(b.text).to_lower().contains("close"):
			b.pressed.emit()


func log_tail(n: int) -> PackedStringArray:
	var log_node := board.get_node_or_null("LogPanel/LogVBox/LogOutput")
	if log_node == null:
		return PackedStringArray()
	var lines: PackedStringArray = log_node.get_parsed_text().strip_edges().split("\n")
	return lines.slice(maxi(0, lines.size() - n))
