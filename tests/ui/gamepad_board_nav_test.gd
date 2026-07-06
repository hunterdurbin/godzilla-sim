extends Node

## Controller board-navigation regression test — ONE graph, ONE cursor.
## Boots a solo GameBoard, flips to gamepad mode with a synthetic joypad
## press, then drives the GamepadBoardNav cursor with injected pad_* actions:
##   - zones_target prompt jails the cursor to valid zones (graph
##     skip-through + sorted-cycle fallback), pad_confirm toggles through
##     Slot.slot_clicked;
##   - free browse walks the map (board rows, hand, action-panel buttons,
##     log panel, tracker labels) with NO control ever holding real focus;
##   - bumpers: LB focuses the log (dpad scrolls), RB the tracker (A toggles
##     a setting), same bumper / B returns the cursor — including during
##     prompts, where the jail is suspended and restored;
##   - sorted hand keeps the same card under the cursor; post-play return
##     lands left neighbor -> right neighbor -> Sort button (as a cursor
##     stop, not focus);
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


## Physical B press — unlike an injected pad_cancel action, this runs the
## full GamepadInput chain (pad_cancel + the mirrored ui_cancel the board's
## cancel ladder listens for).
func _press_b() -> void:
	var b_down := InputEventJoypadButton.new()
	b_down.button_index = JOY_BUTTON_B
	b_down.pressed = true
	Input.parse_input_event(b_down)
	await _tick(3)
	var b_release := InputEventJoypadButton.new()
	b_release.button_index = JOY_BUTTON_B
	b_release.pressed = false
	Input.parse_input_event(b_release)
	await _tick(2)


## THE FOCUS INVARIANT: while the board owns input, nothing holds real focus.
func _assert_no_focus(board: Node, context: String) -> void:
	assert(board.get_viewport().gui_get_focus_owner() == null,
		"real focus held on the board (%s): %s" % [context,
			str(board.get_viewport().gui_get_focus_owner())])


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
	assert(nav._cursor != null and nav._cursor.visible, "gamepad mode did not place the cursor")
	_assert_no_focus(board, "gamepad takeover")

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

	# --- Bumpers work DURING the prompt: LB jumps to the log, movement is
	# restricted to the bumper region, B returns and restores the jail ---
	await _tap(&"pad_focus_log")
	assert(nav._element == "log_panel", "LB did not focus the log panel: %s" % nav._element)
	var log_out: RichTextLabel = board.log_output
	var scroll_before: float = log_out.get_v_scroll_bar().value
	await _tap(&"pad_nav_up")
	assert(nav._element == "log_panel", "dpad left the log during a prompt")
	assert(log_out.get_v_scroll_bar().value <= scroll_before,
		"dpad up did not scroll the log upward")
	await _tap(&"pad_nav_right")
	assert(nav._element == "log_panel", "jail suspension let the cursor onto the board")
	await _press_b()
	assert(nav._element == "bot_z2", "B did not return the cursor from the log: %s" % nav._element)
	assert(nav._mode == "zones_target", "bumper return broke the prompt jail")
	assert(sel._zones_target_selecting, "B during bumper focus leaked into the prompt-skip ladder")

	# Same bumper toggles back out too.
	await _tap(&"pad_focus_log")
	assert(nav._element == "log_panel", "second LB did not re-focus the log")
	await _tap(&"pad_focus_log")
	assert(nav._element == "bot_z2", "same-bumper press did not return the cursor")

	# End the prompt so browse mode resumes.
	sel._finish_zones_target()
	await _tick(2)
	assert(nav._mode == "none", "context did not clear after prompt")

	# --- Free browse: map round trip bottom -> top -> bottom (divider seams
	# pair true screen columns: bot_z8 sits under top_z8) ---
	nav._enter_element("bot_z3")
	await _tick(1)
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z8", "bot_z3 up should be bot_z8: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z8", "bot_z8 up should be top_z8: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z3", "top_z8 up should be top_z3: %s" % nav._element)
	await _tap(&"pad_nav_down")
	assert(nav._element == "top_z8", "top_z3 down should be top_z8: %s" % nav._element)
	await _tap(&"pad_nav_down")
	assert(nav._element == "bot_z8", "top_z8 down should be bot_z8: %s" % nav._element)

	# Rage and deck are cursor stops.
	nav._enter_element("bot_rage")
	await _tick(1)
	assert(nav._cursor.visible, "rage is not a cursor stop")
	await _tap(&"pad_nav_up")
	assert(nav._element == "top_z7", "bot_rage up should be top_z7: %s" % nav._element)

	# --- Spatial seams: board -> log panel -> board, board -> tracker ---
	nav._enter_element("bot_strategy_0")
	await _tick(1)
	await _tap(&"pad_nav_left")
	assert(nav._element == "log_panel", "left off the strategy column should hit the log: %s" % nav._element)
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_strategy_0",
		"right off the log should return (history): %s" % nav._element)
	nav._enter_element("bot_deck")
	await _tick(1)
	await _tap(&"pad_nav_right")
	assert(nav._element.begins_with("trk_"),
		"right off bot_deck should reach the tracker: %s" % nav._element)
	_assert_no_focus(board, "tracker stop")
	await _tap(&"pad_nav_left")
	assert(nav._element == "bot_deck", "left off the tracker should return: %s" % nav._element)

	# --- RB focuses the tracker; A toggles the setting under the cursor ---
	await _tap(&"pad_focus_tracker")
	assert(nav._element.begins_with("trk_"), "RB did not focus the tracker: %s" % nav._element)
	var tracker: Node = board.get_node("TurnTrackerModule")
	var label: Label = tracker.interactive_labels()[nav._id_index(nav._element)]
	var setting: String = label.get_meta("setting")
	var pid: int = label.get_meta("player_id")
	var before: bool = tracker.player_settings[pid][setting]
	await _tap(&"pad_confirm")
	assert(tracker.player_settings[pid][setting] != before, "A did not toggle the tracker setting")
	await _tap(&"pad_confirm")
	assert(tracker.player_settings[pid][setting] == before, "second A did not toggle back")
	# B returns and must NOT open the leave dialog.
	await _press_b()
	assert(not nav._element.begins_with("trk_"), "B did not leave the tracker")
	assert(not board._leave_dialog.visible, "bumper B-return leaked into the cancel ladder")

	# --- Opposite bumper switches regions, return point survives ---
	nav._enter_element("bot_z4")
	await _tick(1)
	await _tap(&"pad_focus_log")
	await _tap(&"pad_focus_tracker")
	assert(nav._element.begins_with("trk_"), "RB did not switch bumper focus to the tracker")
	await _tap(&"pad_focus_tracker")
	assert(nav._element == "bot_z4", "return point lost across bumper switch: %s" % nav._element)

	# --- Action panel buttons are cursor stops (no real focus) ---
	nav._enter_element("ap_end_main")
	await _tick(1)
	assert(nav._cursor.visible, "action button is not a cursor stop")
	_assert_no_focus(board, "cursor on End Main")
	await _tap(&"pad_nav_down")
	assert(nav._element == "ap_sort_hand", "End Main down should reach Sort: %s" % nav._element)
	await _tap(&"pad_nav_left")
	assert(nav._element == "ap_hand_toggle", "Sort left should reach the hand toggle: %s" % nav._element)
	await _tap(&"pad_nav_left")
	assert(nav._element.begins_with("hand_"), "hand toggle left should enter the hand: %s" % nav._element)

	# --- Hand memory: down into the hand, up returns where you came from ---
	nav._enter_element("bot_z4")
	await _tick(1)
	await _tap(&"pad_nav_down")
	assert(nav._element.begins_with("hand_"), "bot_z4 down should enter the hand")
	var hand_ctl: Node = board.get_node("HandController")
	assert(not hand_ctl.hand_expanded, "hand browsing must not auto-expand the hand")
	_assert_no_focus(board, "hand browsing")
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z4", "hand up should return to bot_z4 (history): %s" % nav._element)

	# --- Sorted hand keeps the same card under the cursor ---
	var hand: CardManager = board.player1_hand
	if hand.managed_cards.size() >= 3:
		hand.enter_selection_mode([0, 2] as Array[int])
		nav._enter_element("hand_0")
		await _tick(1)
		var card_under_cursor: Control = nav._cursor_card
		assert(card_under_cursor == hand.managed_cards[0], "cursor not on first valid card")
		hand.managed_cards.reverse()
		hand.arrange_cards(false)
		await _tick(1)
		assert(nav._cursor_card == card_under_cursor, "cursor lost its card across sort")
		assert(nav._hand_index() == hand.managed_cards.find(card_under_cursor),
			"cursor index not rebound after sort: %d" % nav._hand_index())
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
	nav._enter_element("hand_0")
	await _tick(2)
	var hovered: Control = nav._hovered_card
	assert(hovered != null and hovered == nav._cursor_card, "cursor did not hover its card")
	assert(hovered.z_index == 50, "hovered card not raised (z_index %d)" % hovered.z_index)
	if hand.managed_cards.size() >= 2:
		await _tap(&"pad_nav_right")
		assert(nav._hovered_card != hovered, "hover did not move with the cursor")
		assert(hovered.z_index != 50 or hovered == nav._hovered_card,
			"previous card kept its raised z_index")
	nav._enter_element("ap_end_main")
	await _tick(1)
	assert(nav._hovered_card == null, "leaving the hand did not unhover")

	# --- Button churn: the element under the cursor disabling relocates the
	# cursor deterministically, with no focus stolen ---
	nav._enter_element("bot_z2")
	await _tick(1)
	nav._enter_element("ap_end_main")
	await _tick(1)
	sel._disable_all_buttons()
	await _tick(2)
	assert(nav._element != "ap_end_main", "cursor stayed on a disabled button")
	assert(nav._element == "bot_z2",
		"churn relocation should pick the history element: %s" % nav._element)
	_assert_no_focus(board, "after button churn")
	sel._update_action_buttons(sel.turn_manager.rules_engine.get_valid_actions(sel.turn_manager.game_state))
	await _tick(1)

	# --- Direct play from hand browse (A dispatches by card type) ---
	# Deterministic across deck shuffles: drive A on a BATTLE card, which
	# always enters zone selection with the card preselected (never resolves
	# an effect mid-test), then cancel back out. The post-play cursor rules
	# are covered deterministically by cases A/B/C below.
	var battle_idx := -1
	for i in range(hand.managed_cards.size()):
		var candidate: Control = hand.managed_cards[i]
		if "card_data" in candidate \
				and int(candidate.card_data.get("card_type", -1)) == CardEnums.CardType.BATTLE:
			battle_idx = i
			break
	if battle_idx >= 0:
		nav._enter_element("hand_%d" % battle_idx)
		await _tick(1)
		await _tap(&"pad_confirm")
		await _tick(3)
		assert(not sel.waiting_for_card_select, "direct play left card selection dangling")
		if sel.waiting_for_zone_select:
			await _press_b()
			assert(not sel.waiting_for_zone_select, "cancel did not exit zone selection")
		assert(nav._is_active(), "module wedged after direct play")

	# --- Post-play cursor rule: left neighbor -> right neighbor -> Sort ---
	# Case A: context clears while the card is still in the hand (visual
	# removal lags the submit) — cursor returns onto the origin card, then
	# the reorder rule moves it to the LEFT neighbor when the card leaves.
	if hand.managed_cards.size() >= 3:
		nav._enter_element("hand_1")
		await _tick(1)
		var played: Control = hand.managed_cards[1]
		nav._pending_hand_return = true
		nav._play_origin_index = 1
		nav._play_origin_card = played
		nav._enter_element("ap_end_main") # simulate the cursor being pulled away mid-play
		await _tick(1)
		sel._emit_ctx("none")
		await _tick(1)
		assert(nav._element == "hand_1", "cursor did not return to the origin card: %s" % nav._element)
		# The post-action button refresh must NOT steal focus or move the
		# cursor while it owns the hand.
		GamepadHelper.refocus()
		await _tick(2)
		_assert_no_focus(board, "refocus while cursor in hand")
		assert(nav._element == "hand_1", "refocus knocked the cursor out of the hand")
		hand.remove_card(played, false)
		played.queue_free()
		hand.arrange_cards(false)
		await _tick(1)
		assert(nav._element == "hand_0",
			"cursor should land on the LEFT neighbor after the card leaves: %s" % nav._element)

	# Case B: context clears after the card already left (index 0 played —
	# no left neighbor, the right neighbor slid into slot 0).
	if hand.managed_cards.size() >= 2:
		var played_b: Control = hand.managed_cards[0]
		nav._pending_hand_return = true
		nav._play_origin_index = 0
		nav._play_origin_card = played_b
		nav._enter_element("ap_end_main")
		await _tick(1)
		hand.remove_card(played_b, false)
		played_b.queue_free()
		hand.arrange_cards(false)
		await _tick(1)
		sel._emit_ctx("none")
		await _tick(1)
		assert(nav._element == "hand_0",
			"cursor should land on the right neighbor at slot 0: %s" % nav._element)

	# Case C: last card played -> the Sort button becomes the cursor stop
	# (a cursor stop, never real focus).
	while hand.managed_cards.size() > 1:
		var extra: Control = hand.managed_cards.back()
		hand.remove_card(extra, false)
		extra.queue_free()
	hand.arrange_cards(false)
	await _tick(1)
	nav._enter_element("hand_0")
	await _tick(1)
	var last_card: Control = hand.managed_cards[0]
	nav._pending_hand_return = true
	nav._play_origin_index = 0
	nav._play_origin_card = last_card
	hand.remove_card(last_card, false)
	last_card.queue_free()
	hand.arrange_cards(false)
	await _tick(1)
	sel._emit_ctx("none")
	await _tick(2)
	assert(nav._element == "ap_sort_hand",
		"empty hand should park the cursor on the Sort button: %s" % nav._element)
	assert(nav._cursor.visible, "Sort button cursor stop not visible")
	_assert_no_focus(board, "empty-hand Sort stop")

	# --- F3 debug overlay: paints without stealing input or focus ---
	var debug_overlay: Node = board.get_node_or_null("NavDebugOverlay")
	if debug_overlay and OS.is_debug_build():
		var f3 := InputEventKey.new()
		f3.keycode = KEY_F3
		f3.physical_keycode = KEY_F3
		f3.pressed = true
		Input.parse_input_event(f3)
		await _tick(2)
		assert(debug_overlay.visible, "F3 did not show the nav debug overlay")
		assert(nav._is_active(), "debug overlay suspended the nav module")
		var f3_up := InputEventKey.new()
		f3_up.keycode = KEY_F3
		f3_up.physical_keycode = KEY_F3
		f3_up.pressed = false
		Input.parse_input_event(f3_up)
		await _tick(1)
		f3.pressed = true
		Input.parse_input_event(f3)
		await _tick(2)
		assert(not debug_overlay.visible, "second F3 did not hide the overlay")

	print("GAMEPAD_NAV_TEST_PASS")
	get_tree().quit(0)
