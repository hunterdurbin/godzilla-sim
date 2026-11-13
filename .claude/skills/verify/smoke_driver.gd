extends Node
## Smoke driver for smoke.sh: starts a real solo GameBoard, ends the main
## phase for N turns (closing effect overlays), screenshots start and end.
## User args: --turns=N --shots=<dir>. Prints "[Smoke] ..." lines for the
## shell side; "[Smoke] DONE" is the completion marker.

var board: Node
var turns: int = 4
var shots_dir: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--turns="):
			turns = int(arg.get_slice("=", 1))
		elif arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
	board = load("res://scenes/board/GameBoard.tscn").instantiate()
	add_child(board)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_shot("start")
	for i in range(turns):
		var pid: int = board._get_current_pid()
		if board.btn_end_main.is_visible_in_tree() and not board.btn_end_main.disabled:
			board.btn_end_main.pressed.emit()
		var flipped := false
		for _t in range(40):
			await get_tree().create_timer(0.2).timeout
			_close_overlays()
			if board._get_current_pid() != pid:
				flipped = true
				break
		var gs: GameState = board.turn_manager.game_state
		if not flipped:
			print("[Smoke] STALL turn=%d pid=%d" % [gs.turn_number, pid])
			_shot("stall")
			break
		print("[Smoke] turn=%d pid=%d" % [gs.turn_number, board._get_current_pid()])
	_shot("end")
	print("[Smoke] DONE")
	get_tree().quit()


func _close_overlays() -> void:
	for b: Button in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and String(b.text).to_lower().contains("close"):
			b.pressed.emit()


func _shot(label: String) -> void:
	if shots_dir.is_empty():
		return
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join("smoke_%s.png" % label))
	print("[Smoke] shot %s" % shots_dir.path_join("smoke_%s.png" % label))
