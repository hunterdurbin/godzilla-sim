extends Node

## Controller board-navigation regression test — the cursor follows the
## BoardCursorMap adjacency graph. Boots a solo GameBoard, flips to gamepad
## mode with a synthetic joypad press, then drives the GamepadBoardNav
## cursor with injected pad_* actions:
##   - zones_target prompt jails the cursor to valid zones (graph
##     skip-through + sorted-cycle fallback), pad_confirm toggles through
##     Slot.slot_clicked;
##   - free browse walks the map (bottom -> top board round trip), hand
##     memory returns the cursor where it came from;
##   - sorted hand keeps the same card under the cursor;
##   - registered modal dialogs suspend the module; text fields release on
##     any dpad press.
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/GamepadBoardNavTest.tscn

func _inject_action(action: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap(action: StringName) -> void:
	_inject_action(action, true)
	await _tick(2)
	_inject_action(action, false)
	await _tick(1)


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

	# --- zones_target prompt rides the graph, jailed to valid zones ---
	# Valid zones Z2/Z4/Z6 on player 0's (bottom) board.
	var valid: Array[int] = [1, 3, 5]
	sel._show_zones_target_selection(0, 0, valid, 3, false, "pick zones")
	await _tick(2)
	assert(nav._mode == "zones_target", "module missed selection context: %s" % nav._mode)
	assert(nav._element == "bot_z2", "cursor not on first valid zone: %s" % nav._element)
	assert(nav._cursor != null and nav._cursor.visible, "no visible cursor")

	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1], "confirm did not select zone 2: %s" % str(sel._zones_target_selected))

	# Right skips invalid Z3 via the graph and lands on Z4.
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z4", "right did not skip to bot_z4: %s" % nav._element)
	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1, 3], "second confirm failed: %s" % str(sel._zones_target_selected))

	# Z6 sits in the other row — the graph dead-ends rightward, so the
	# sorted-cycle fallback must still reach it, then wrap to Z2.
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z6", "fallback cycle did not reach bot_z6: %s" % nav._element)
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z2", "cycle did not wrap to bot_z2: %s" % nav._element)

	# End the prompt so browse mode resumes.
	sel._finish_zones_target()
	await _tick(2)
	assert(nav._mode == "none", "context did not clear after prompt")

	# --- Free browse: map round trip bottom -> top -> bottom ---
	nav._enter_element("bot_z3")
	await _tick(1)
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z8", "bot_z3 up should be bot_z8: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z7", "bot_z8 up should be top_z7: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z4", "top_z7 up should be top_z4: %s" % nav._element)
	await _tap(&"pad_nav_down")
	assert(nav._element == "top_z7", "top_z4 down should be top_z7: %s" % nav._element)
	await _tap(&"pad_nav_down")
	assert(nav._element == "bot_z8", "top_z7 down should be bot_z8: %s" % nav._element)

	# Rage and deck are cursor stops now.
	nav._enter_element("bot_rage")
	await _tick(1)
	assert(nav._cursor.visible, "rage is not a cursor stop")
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z6", "bot_rage up should be top_z6: %s" % nav._element)

	# --- Hand memory: down into the hand, up returns where you came from ---
	nav._enter_element("bot_z4")
	await _tick(1)
	await _tap(&"pad_nav_down")
	assert(nav._region == nav.Region.HAND, "bot_z4 down should enter the hand")
	var hand_ctl: Node = board.get_node("HandController")
	assert(not hand_ctl.hand_expanded, "hand browsing must not auto-expand the hand")
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z4", "hand up should return to bot_z4 (history): %s" % nav._element)
	nav._enter_action_panel()
	await _tick(1)

	# --- Sorted hand keeps the same card under the cursor ---
	var hand: CardManager = board.player1_hand
	if hand.managed_cards.size() >= 3:
		hand.enter_selection_mode([0, 2] as Array[int])
		nav._enter_hand()
		await _tick(1)
		var card_under_cursor: Control = nav._cursor_card
		assert(card_under_cursor == hand.managed_cards[0], "cursor not on first valid card")
		hand.managed_cards.reverse()
		hand.arrange_cards(false)
		await _tick(1)
		assert(nav._cursor_card == card_under_cursor, "cursor lost its card across sort")
		assert(nav._hand_index == hand.managed_cards.find(card_under_cursor),
			"cursor index not rebound after sort: %d" % nav._hand_index)
		var last := hand.managed_cards.size() - 1
		var expected_valid: Array[int] = [last - 2, last]
		assert(hand.selectable_indices == expected_valid,
			"selectable_indices not remapped: %s" % str(hand.selectable_indices))
		hand.exit_selection_mode()

	# --- Overlays and registered modals suspend the module ---
	board.discard_view_overlay.show_cards([], "test")
	await _tick(1)
	assert(not nav._is_active(), "module still active with overlay open")
	board.discard_view_overlay.try_close()
	await _tick(1)
	assert(nav._is_active(), "module did not resume after overlay closed")

	board._leave_dialog.popup_centered()
	await _tick(2)
	assert(not nav._is_active(), "module still active under Leave dialog")
	assert(not GamepadHelper.is_top_context(board), "board still top context under dialog")
	board._leave_dialog.hide()
	await _tick(2)
	assert(nav._is_active(), "module did not resume after Leave dialog closed")

	# --- Chat/LineEdit trap: any dpad press escapes a focused text field ---
	assert(board.chat_input.focus_mode == Control.FOCUS_CLICK,
		"chat must not be dpad-focusable")
	board.chat_input.grab_focus()
	await _tick(1)
	assert(board.chat_input.has_focus(), "chat did not take programmatic focus")
	var dpad := InputEventJoypadButton.new()
	dpad.button_index = JOY_BUTTON_DPAD_LEFT
	dpad.pressed = true
	Input.parse_input_event(dpad)
	await _tick(2)
	assert(not board.chat_input.has_focus(), "dpad press did not escape the chat field")
	assert(not board._leave_dialog.visible, "escaping chat must not open the leave dialog")
	var dpad_up := InputEventJoypadButton.new()
	dpad_up.button_index = JOY_BUTTON_DPAD_LEFT
	dpad_up.pressed = false
	Input.parse_input_event(dpad_up)
	await _tick(1)

	board.chat_input.grab_focus()
	await _tick(1)
	var b_btn := InputEventJoypadButton.new()
	b_btn.button_index = JOY_BUTTON_B
	b_btn.pressed = true
	Input.parse_input_event(b_btn)
	await _tick(2)
	assert(not board.chat_input.has_focus(), "B did not escape the chat field")
	assert(not board._leave_dialog.visible, "chat B-escape leaked into the ui_cancel ladder")
	var b_up := InputEventJoypadButton.new()
	b_up.button_index = JOY_BUTTON_B
	b_up.pressed = false
	Input.parse_input_event(b_up)
	await _tick(1)

	# --- Hover-raise: the cursor drives the mouse hover tween ---
	nav._enter_hand()
	await _tick(2)
	var hovered: Control = nav._hovered_card
	assert(hovered != null and hovered == nav._cursor_card, "cursor did not hover its card")
	assert(hovered.z_index == 50, "hovered card not raised (z_index %d)" % hovered.z_index)
	if hand.managed_cards.size() >= 2:
		await _tap(&"pad_nav_right")
		assert(nav._hovered_card != hovered, "hover did not move with the cursor")
		assert(hovered.z_index != 50 or hovered == nav._hovered_card,
			"previous card kept its raised z_index")
	nav._enter_action_panel()
	await _tick(1)
	assert(nav._hovered_card == null, "leaving the hand did not unhover")

	# --- Group hops ---
	# Board group has no right edge: the cursor stays put at bot_deck.
	nav._enter_element("bot_deck")
	await _tick(1)
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_deck", "board right edge should be a wall: %s" % nav._element)
	# Hand -> up uses element edges; ACTION_PANEL left/down edge -> hand group.
	nav._enter_action_panel()
	await _tick(1)
	_inject_action(&"pad_nav_down")
	await _tick(2)
	_inject_action(&"pad_nav_down", false)
	await _tick(1)
	if nav._region != nav.Region.HAND:
		# Focus may have moved within the panel first; press again from the edge.
		_inject_action(&"pad_nav_down")
		await _tick(2)
		_inject_action(&"pad_nav_down", false)
		await _tick(1)
	assert(nav._region == nav.Region.HAND, "panel down edge did not hop to the hand group")

	# --- Direct play from hand browse (A dispatches by card type) ---
	nav._enter_hand()
	await _tick(1)
	var hand_size_before: int = hand.managed_cards.size()
	var play_card: Control = nav._hand_card(nav._hand_index)
	assert(play_card != null, "no hand card to play")
	await _tap(&"pad_confirm")
	await _tick(3)
	var entered_zone_select: bool = sel.waiting_for_zone_select
	var entered_card_select: bool = sel.waiting_for_card_select
	assert(not entered_card_select, "direct play left card selection dangling")
	if entered_zone_select:
		# Battle card: zone selection started with the card preselected —
		# cancel out and confirm nothing is stuck.
		await _tap(&"pad_cancel")
		assert(not sel.waiting_for_zone_select, "cancel did not exit zone selection")
	elif hand.managed_cards.size() < hand_size_before:
		# Card left the hand from index 0: no left neighbor, so the cursor
		# lands on the card that slid into its slot (index 0).
		assert(nav._region == nav.Region.HAND, "cursor left the hand after play")
		assert(nav._hand_index == 0,
			"cursor should land on the right neighbor after playing index 0: %d" % nav._hand_index)
		assert(is_instance_valid(nav._cursor_card) and nav._cursor_card == hand.managed_cards[0],
			"cursor card not rebound after play")
	assert(nav._is_active(), "module wedged after direct play")

	print("GAMEPAD_NAV_TEST_PASS")
	get_tree().quit(0)
