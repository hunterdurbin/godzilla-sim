extends Node

## Regression test for the effect-choice panel geometry. Boots a solo
## GameBoard, shows a two-option choice with card thumbnails, and asserts
## the panel is fully on screen, sits above the hand toggle/sort buttons,
## and hugs its content height (no gap under the last button).
##
## Run:
##   godot --headless --quit-after 1800 res://scenes/board/tests/ChoicePanelGeometryTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var board: Node = load("res://scenes/board/GameBoard.tscn").instantiate()
	get_tree().root.add_child(board)
	# Let the solo game boot + layout settle
	for i in range(30):
		await get_tree().process_frame
	var sel: Node = board.get_node("SelectionController")
	var ids: Array[String] = ["EBP04-089", "EBP04-089"]
	var opts: Array[String] = ["Inherited Life (Strategy 1)", "Inherited Life (Strategy 2)"]
	sel._show_choice_selection(0, opts, "Choose ability", ids)
	for i in range(5):
		await get_tree().process_frame

	var panel: PanelContainer = sel._choice_panel
	assert(panel != null and is_instance_valid(panel), "no choice panel")
	var pr: Rect2 = panel.get_global_rect()
	var vp: Rect2 = board.get_viewport_rect()
	print("viewport=", vp, " panel=", pr)
	assert(pr.position.y >= 0.0, "panel top above screen: %s" % pr)
	assert(pr.end.y <= vp.size.y + 0.5, "panel bottom off screen: %s vs %s" % [pr, vp])
	assert(pr.end.x <= vp.size.x + 0.5, "panel right off screen")
	assert(pr.size.y >= 100.0, "panel collapsed: %s" % pr)

	# Above the hand toggle/sort buttons
	for hb in [board.hand_toggle_button, board.sort_hand_button]:
		if hb and hb.visible:
			var br: Rect2 = hb.get_global_rect()
			assert(pr.end.y <= br.position.y + 0.5, "panel overlaps hand button: panel=%s btn=%s" % [pr, br])

	# The prompt header lives INSIDE the panel now — the bottom-left
	# ActionPrompt must stay hidden during a choice.
	var header: Label = panel.get_node("ChoiceInner/ChoiceHeader")
	assert(header != null and header.visible, "no header inside choice panel")
	assert(header.text == "Choose ability", "header text mismatch: %s" % header.text)
	var action_prompt: Control = board.get_node("ActionPrompt")
	assert(not action_prompt.visible, "ActionPrompt visible during choice")

	# No big gap under the buttons: panel height ~= header + content + margins
	# (20 stylebox margins + 6 separation between header and scroll).
	var content_h: float = sel._choice_container.size.y + header.size.y + 26.0
	assert(absf(pr.size.y - content_h) <= 12.0, "gap mismatch: panel_h=%f content=%f" % [pr.size.y, content_h])

	print("CHOICE_GEOM_TEST_PASS")
	get_tree().quit(0)
