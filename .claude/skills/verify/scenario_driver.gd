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
##   await v.act(action, params)   submit a CardEnums.ActionType through
##            tm.submit_action once the engine awaits an action, close the
##            overlays it opens, and wait for the next AWAITING_ACTION.
##            Params: PLAY_BATTLE {hand_index, zone_index}; PLAY_STRATEGY /
##            GAIN_RAGE / PLAY_MONSTER / INVADE {hand_index}
##            (scripts/core/action_handler.gd execute()).
##   await v.check_sync(pid, label) -> bool   rendered hand / zones vs
##            PlayerState; prints "[Scenario] <label> ... ok|MISMATCH" and
##            takes shot <label>.
## Answering a prompt through tm.player_input.resolve_* resolves the engine
## but leaves its UI overlay open (close_overlays() only presses "close"
## buttons).

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


## Submits `action` once the engine awaits an action, then waits for the
## next AWAITING_ACTION, closing any overlay the action opened.
func act(action: int, params: Dictionary) -> void:
	await _until_awaiting_action()
	tm.submit_action(action, params)
	await wait(1.0)
	close_overlays()
	await _until_awaiting_action()


## True when player `pid`'s rendered hand count and zone occupancy match
## PlayerState (the monster's zone is skipped). Prints one line, takes a shot.
func check_sync(pid: int, label: String) -> bool:
	await wait(0.5)
	var ps: PlayerState = gs.players[pid]
	var pboard: Node = board.player1_board if pid == 0 else board.player2_board
	var shown_hand: int = pboard.hand_manager.get_card_count()
	var zone_bad: Array[int] = []
	for i in range(pboard.zone_slots.size()):
		if i == ps.monster_zone - 1:
			continue
		if pboard.zone_slots[i].has_card() != ps.zone_has_cards(i):
			zone_bad.append(i + 1)
	var in_sync := shown_hand == ps.hand.size() and zone_bad.is_empty()
	note("%s hand state=%d shown=%d zone mismatches=%s %s" % [
		label, ps.hand.size(), shown_hand, zone_bad, "ok" if in_sync else "MISMATCH"])
	shot(label)
	return in_sync


func _until_awaiting_action() -> void:
	for _i in range(40):
		if tm.flow_state == TurnManager.FlowState.AWAITING_ACTION:
			return
		close_overlays()
		await wait(0.25)
	note("WARN not awaiting action (flow_state=%d)" % tm.flow_state)
