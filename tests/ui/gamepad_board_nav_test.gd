extends Node

## Controller board-navigation regression test. Boots a solo GameBoard,
## flips the input mode to gamepad with a synthetic joypad press, opens a
## multi-zone (zones_target) prompt, and drives the GamepadBoardNav cursor
## with injected pad_* actions: the cursor must jail itself to the prompt's
## valid zones and pad_confirm must toggle selection through the same
## Slot.slot_clicked path the mouse uses. Also asserts an open overlay
## suspends the module.
##
## Run:
##   godot --headless --quit-after 1800 res://tests/ui/GamepadBoardNavTest.tscn

func _inject_action(action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tick(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var board: Node = load("res://scenes/board/GameBoard.tscn").instantiate()
	get_tree().root.add_child(board)
	await _tick(30) # solo game boot + layout settle

	# Flip to gamepad mode with a synthetic physical press (A button).
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	Input.parse_input_event(joy)
	await _tick(2)
	assert(GamepadHelper.is_using_gamepad(), "joypad press did not enter gamepad mode")

	var sel: Node = board.get_node("SelectionController")
	var nav: Node = board.get_node("GamepadBoardNav")
	assert(nav != null, "GamepadBoardNav module missing from GameBoard")
	assert(nav._is_active(), "module inactive with no overlay open")

	# Multi-zone prompt on player 0's board: zones 1/3/5, pick exactly 2.
	var valid: Array[int] = [1, 3, 5]
	sel._show_zones_target_selection(0, 0, valid, 2, false, "pick zones")
	await _tick(2)
	assert(nav._mode == "zones_target", "module missed selection context: %s" % nav._mode)
	assert(nav._index == 1, "cursor not on first valid zone: %d" % nav._index)
	assert(nav._cursor != null and nav._cursor.visible, "no visible cursor")

	# Confirm toggles zone 1 through Slot.slot_clicked.
	_inject_action(&"pad_confirm")
	await _tick(2)
	_inject_action(&"pad_confirm", false)
	await _tick(1)
	assert(sel._zones_target_selected == [1], "confirm did not select zone 1: %s" % str(sel._zones_target_selected))

	# Right skips invalid zone 2 and lands on 3; confirm adds it.
	_inject_action(&"pad_nav_right")
	await _tick(2)
	_inject_action(&"pad_nav_right", false)
	await _tick(1)
	assert(nav._index == 3, "nav_right did not skip to next valid zone: %d" % nav._index)
	_inject_action(&"pad_confirm")
	await _tick(2)
	_inject_action(&"pad_confirm", false)
	await _tick(1)
	assert(sel._zones_target_selected == [1, 3], "second confirm failed: %s" % str(sel._zones_target_selected))

	# Wrap: two more rights loop 5 -> 1.
	for i in range(2):
		_inject_action(&"pad_nav_right")
		await _tick(2)
		_inject_action(&"pad_nav_right", false)
		await _tick(1)
	assert(nav._index == 1, "valid-zone wrap failed: %d" % nav._index)

	# An open overlay suspends the module.
	board.discard_view_overlay.show_cards([], "test")
	await _tick(1)
	assert(not nav._is_active(), "module still active with overlay open")
	board.discard_view_overlay.try_close()
	await _tick(1)
	assert(nav._is_active(), "module did not resume after overlay closed")

	print("GAMEPAD_NAV_TEST_PASS")
	get_tree().quit(0)
