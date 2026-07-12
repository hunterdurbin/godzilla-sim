extends Node

## Controller board-navigation regression test — ONE graph, ONE cursor.
## Boots a solo GameBoard, flips to gamepad mode with a synthetic joypad
## press, then drives the GamepadBoardNav cursor with injected pad_* actions:
##   - zones_target prompt jails the cursor to the target board's FULL z1-z8
##     (wrap-around ZONE_JAIL_EDGES rows; invalid zones are cursor stops,
##     confirm on them is a no-op), pad_confirm toggles valid zones through
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
##     any dpad press;
##   - effects area: pending-stack rows are cursor stops, the choice jail
##     spans choice+stack, Select cycles effects <-> board (read-only roam
##     during a mandatory choice: A opens the pile/stack viewers, plays and
##     End Main stay dead, B returns), the ring sits on the choice button's
##     REAL rect from the first settled frame, and the Select hint rows
##     name their destination.
##
## Set VERIFY_SHOT_DIR to capture screenshots at the effects-area steps
## (headful runs only).
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


## Optional visual evidence for headful verification runs (no-op headless
## or without VERIFY_SHOT_DIR).
func _shot(shot_name: String) -> void:
	var dir := OS.get_environment("VERIFY_SHOT_DIR")
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))


## The single Label inside an OverlayHintRow (its glyph+label pairs).
func _hint_text(row: Control) -> String:
	for child in row.get_children():
		if child is Label:
			return (child as Label).text
	return ""


## Physical button press — unlike an injected pad_* action, this runs the
## full GamepadInput chain (logical action + any mirrored ui_* twins).
func _press_physical(button_index: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button_index
	down.pressed = true
	Input.parse_input_event(down)
	await _tick(3)
	var release := InputEventJoypadButton.new()
	release.button_index = button_index
	release.pressed = false
	Input.parse_input_event(release)
	await _tick(2)


func _press_b() -> void:
	await _press_physical(JOY_BUTTON_B)


## THE FOCUS INVARIANT: while the board owns input, nothing holds real focus.
func _assert_no_focus(board: Node, context: String) -> void:
	assert(board.get_viewport().gui_get_focus_owner() == null,
		"real focus held on the board (%s): %s" % [context,
			str(board.get_viewport().gui_get_focus_owner())])


func _ready() -> void:
	# Hermetic bindings: a connected controller loads the USER'S persisted
	# rebinds (user://settings.cfg) — the walk assumes the default map.
	# In-memory only; never touches the saved config.
	GamepadInput._map = GlyphDB.default_map()
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

	# --- zones_target prompt rides the zone-jail graph: ALL of z1-z8 are
	# cursor stops, only valid zones act on confirm ---
	# Valid zones Z2/Z4/Z6 on player 0's (bottom) board.
	var valid: Array[int] = [1, 3, 5]
	sel._show_zones_target_selection(0, 0, valid, 3, false, "pick zones")
	await _tick(2)
	assert(nav._mode == "zones_target", "module missed selection context: %s" % nav._mode)
	assert(nav._element == "bot_z2", "cursor not on first valid zone: %s" % nav._element)
	assert(nav._cursor != null and nav._cursor.visible, "no visible cursor")
	var hint_cluster: Control = board.get_node("HandHintCluster")
	assert(not hint_cluster.visible, "hand-hint cluster visible during a prompt")
	# A is consumed by the zone toggle here — the Confirm button's glyph must
	# advertise the button that actually presses it (pad_end_main / X).
	assert(board.confirm_glyph.action == &"pad_end_main",
		"Confirm glyph not context-flipped to pad_end_main: %s" % board.confirm_glyph.action)

	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1], "confirm did not select zone 2: %s" % str(sel._zones_target_selected))

	# Invalid Z3 is a cursor stop now, and confirm on it is a silent no-op.
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z3", "right did not stop on invalid bot_z3: %s" % nav._element)
	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1], "confirm on an invalid zone selected something: %s" % str(sel._zones_target_selected))

	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z4", "right did not reach bot_z4: %s" % nav._element)
	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1, 3], "second confirm failed: %s" % str(sel._zones_target_selected))

	# The jail rows wrap: z5 -> z1 horizontally, z1 jumps up to z8 (one-way),
	# z8 wraps left to z6, and the vertical wrap lifts z6 back to z5.
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z5", "right did not reach bot_z5: %s" % nav._element)
	await _tap(&"pad_nav_right")
	assert(nav._element == "bot_z1", "lower row did not wrap z5 -> z1: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z8", "z1 up did not jump to z8: %s" % nav._element)
	await _tap(&"pad_nav_left")
	assert(nav._element == "bot_z6", "upper row did not wrap z8 -> z6: %s" % nav._element)
	await _tap(&"pad_nav_up")
	assert(nav._element == "bot_z5", "z6 up did not wrap to z5: %s" % nav._element)
	# Walk back to Z2 for the bumper leg below.
	for i in range(3):
		await _tap(&"pad_nav_left")
	assert(nav._element == "bot_z2", "left walk did not return to bot_z2: %s" % nav._element)

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

	# --- X (pad_end_main) finalizes the selection from inside the jail ---
	# Exact-N prompt: Confirm stays disabled at 2/3, and X falls through to
	# nothing (End Main is disabled during prompts) — the selection survives.
	assert(board.btn_confirm.disabled, "Confirm enabled below the exact count")
	await _press_physical(JOY_BUTTON_X)
	assert(sel._zones_target_selecting, "X below the exact count ended the prompt")
	assert(sel._zones_target_selected == [1, 3], "X below the exact count changed the selection")
	# Third pick: z2 up -> z8, left wraps -> z6 (valid).
	await _tap(&"pad_nav_up")
	await _tap(&"pad_nav_left")
	assert(nav._element == "bot_z6", "walk did not reach bot_z6: %s" % nav._element)
	await _tap(&"pad_confirm")
	assert(sel._zones_target_selected == [1, 3, 5], "third confirm failed: %s" % str(sel._zones_target_selected))
	assert(not board.btn_confirm.disabled, "Confirm still disabled at 3/3")
	await _press_physical(JOY_BUTTON_X)
	assert(not sel._zones_target_selecting, "X at full count did not finalize the prompt")
	assert(nav._mode == "none", "context did not clear after prompt")

	# --- Pass confirmation is the one jail whose cursor sits ON the Confirm
	# button — there the glyph advertises A (pad_confirm) again ---
	sel._enter_pass_confirmation()
	await _tick(2)
	assert(board.confirm_glyph.action == &"pad_confirm",
		"Confirm glyph not restored to pad_confirm in confirm mode: %s" % board.confirm_glyph.action)
	sel._cancel_pass_confirmation()
	await _tick(2)
	assert(board.confirm_glyph.action == &"pad_end_main",
		"Confirm glyph did not flip back after leaving confirm mode: %s" % board.confirm_glyph.action)

	# --- Mixed input leaves no stray focus: a mouse click on a board button
	# grabs REAL focus (the pointer flip releases before the click lands);
	# the next pad press must clear it, or the mirrored ui_* events walk a
	# second focus ring around the panel next to the cursor ---
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(400.0, 400.0)
	motion.velocity = Vector2(60.0, 0.0)
	motion.relative = Vector2(6.0, 0.0)
	Input.parse_input_event(motion)
	await _tick(2)
	assert(not GamepadHelper.is_using_gamepad(), "mouse motion did not flip to pointer mode")
	board.btn_end_main.grab_focus() # what a real click leaves behind
	await _tick(1)
	assert(board.get_viewport().gui_get_focus_owner() == board.btn_end_main,
		"test setup: button did not take focus")
	var retake := InputEventJoypadButton.new()
	retake.button_index = JOY_BUTTON_DPAD_RIGHT
	retake.pressed = true
	Input.parse_input_event(retake)
	await _tick(3)
	var retake_up := InputEventJoypadButton.new()
	retake_up.button_index = JOY_BUTTON_DPAD_RIGHT
	retake_up.pressed = false
	Input.parse_input_event(retake_up)
	await _tick(2)
	assert(GamepadHelper.is_using_gamepad(), "dpad press did not re-enter gamepad mode")
	_assert_no_focus(board, "pad takeover after mouse click-focus")
	assert(nav._cursor != null and nav._cursor.visible, "cursor missing after retakeover")

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
	assert(nav._element.begins_with("hand_"), "End Main down should enter the hand: %s" % nav._element)
	# Vertical Sort/Expand stack: toggle sits above sort, left of the panel.
	nav._enter_element("ap_sort_hand")
	await _tick(1)
	await _tap(&"pad_nav_up")
	assert(nav._element == "ap_hand_toggle", "Sort up should reach the hand toggle: %s" % nav._element)
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
	assert(nav._element == "", "cursor not parked while overlay open")
	board.discard_view_overlay.try_close()
	await _tick(1)
	assert(nav._is_active(), "module did not resume after overlay closed")
	assert(nav._cursor and nav._cursor.visible, "cursor did not restore after overlay closed")

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

	# --- Hand-hint cluster mirrors hand_card_hint_actions() while hovering ---
	assert(hovered == nav.browse_hovered_hand_card(),
		"browse_hovered_hand_card disagrees with the hover state")
	var hints: Array[int] = sel.hand_card_hint_actions(hovered)
	assert(hint_cluster.visible == (not hints.is_empty()),
		"hint cluster visibility diverged from hint actions: %s" % str(hints))
	assert(board.get_node("HandHintCluster/VBox/RowPlay").visible == (
			hints.has(CardEnums.ActionType.PLAY_MONSTER)
			or hints.has(CardEnums.ActionType.PLAY_BATTLE)
			or hints.has(CardEnums.ActionType.PLAY_STRATEGY)),
		"Play hint row diverged from hint actions: %s" % str(hints))
	assert(board.get_node("HandHintCluster/VBox/RowRage").visible
			== hints.has(CardEnums.ActionType.GAIN_RAGE),
		"Rage hint row diverged from hint actions: %s" % str(hints))
	assert(board.get_node("HandHintCluster/VBox/RowInvade").visible
			== hints.has(CardEnums.ActionType.INVADE),
		"Invade hint row diverged from hint actions: %s" % str(hints))

	if hand.managed_cards.size() >= 2:
		await _tap(&"pad_nav_right")
		assert(nav._hovered_card != hovered, "hover did not move with the cursor")
		assert(hovered.z_index != 50 or hovered == nav._hovered_card,
			"previous card kept its raised z_index")
	nav._enter_element("ap_end_main")
	await _tick(1)
	assert(nav._hovered_card == null, "leaving the hand did not unhover")
	assert(not hint_cluster.visible, "hint cluster stayed visible after leaving the hand")

	# --- Modals park the cursor and restore it to the same hand card ---
	nav._enter_element("hand_0")
	await _tick(2)
	var parked_card: Control = nav._cursor_card
	assert(parked_card != null, "no cursor card before the modal-park test")
	board.zone_stack_view_overlay.show_cards([], "test")
	await _tick(2)
	assert(not nav._is_active(), "module still active under zone stack viewer")
	assert(nav._element == "", "cursor not parked under zone stack viewer")
	assert(nav._hovered_card == null, "hand card stayed hovered under the modal")
	assert(parked_card.z_index != 50, "hand card stayed raised under the modal")
	assert(not nav._cursor.visible, "cursor ring stayed visible under the modal")
	assert(not hint_cluster.visible, "hint cluster stayed visible under the modal")
	board.zone_stack_view_overlay.try_close()
	await _tick(2)
	assert(nav._is_active(), "module did not resume after zone stack viewer closed")
	assert(nav._element == "hand_0", "cursor did not return to hand_0: %s" % nav._element)
	assert(nav._cursor_card == parked_card and nav._hovered_card == parked_card,
		"cursor did not restore onto the same hand card")
	assert(nav._cursor.visible, "cursor ring did not restore after modal close")
	_assert_no_focus(board, "after zone stack viewer close")

	# Card zoom is the one suspending overlay WITHOUT register_modal — the
	# direct visibility_changed hook must park/restore the same way.
	await _tap(&"pad_inspect")
	await _tick(2)
	assert(board.card_zoom_overlay.visible, "inspect on a hand card did not open the zoom")
	assert(nav._element == "" and nav._hovered_card == null,
		"cursor not parked under the card zoom")
	assert(not hint_cluster.visible, "hint cluster stayed visible under the card zoom")
	board.card_zoom_overlay.hide_zoom()
	await _tick(2)
	assert(nav._element == "hand_0" and nav._hovered_card == parked_card,
		"cursor did not restore after the card zoom closed")

	# Window modal (leave dialog) over a non-hand element: element-string restore.
	nav._enter_element("bot_z2")
	await _tick(1)
	board._leave_dialog.popup_centered()
	await _tick(2)
	assert(nav._element == "", "cursor not parked under the leave dialog")
	assert(not nav._cursor.visible, "cursor ring stayed visible under the leave dialog")
	board._leave_dialog.hide()
	await _tick(2)
	assert(nav._element == "bot_z2", "cursor did not return to bot_z2: %s" % nav._element)

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
		await _tick(2)
		if nav._element.begins_with("hand_") and not sel.hand_card_hint_actions(
				nav.browse_hovered_hand_card()).is_empty():
			assert(hint_cluster.visible,
				"hint cluster did not re-show after cancel returned the cursor to the hand")

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

	# --- Effects area: stack rows as cursor stops + the Select toggle ---
	var stack: Node = board.get_node("EffectStackPanel")
	var local_pid: int = board.local_player_id
	stack.show_stack([
		{"base_id": "ESD01-016", "label": "Pending A", "player_id": local_pid, "status": "pending"},
		{"base_id": "ESD01-016", "label": "Pending B", "player_id": local_pid + 1, "status": "pending"},
	])
	await _tick(2)
	assert(stack.nav_row_count() == 2, "stack registry did not pick up the rows")

	# Free browse: Select toggles board -> stack -> board, remembering both
	# sides, and must NOT open chat while the effects area is up.
	nav._enter_element("bot_z2")
	await _tick(1)
	await _tap(&"pad_chat")
	assert(nav._element == "stack_0", "Select did not jump to the stack: %s" % nav._element)
	assert(not board.chat_input.has_focus(), "Select opened chat while the effects area is up")
	await _shot("01_stack_focus")
	await _tap(&"pad_nav_down")
	assert(nav._element == "stack_1", "down did not walk the stack column: %s" % nav._element)
	await _tap(&"pad_chat")
	assert(nav._element == "bot_z2", "Select did not return to the board origin: %s" % nav._element)
	await _tap(&"pad_chat")
	assert(nav._element == "stack_1", "Select forgot the effects element: %s" % nav._element)

	# Y on a stack row opens the card zoom (same view as the row right-click).
	await _tap(&"pad_inspect")
	await _tick(2)
	assert(board.card_zoom_overlay.visible, "Y on a stack row did not open the card zoom")
	board.card_zoom_overlay.hide_zoom()
	await _tick(2)

	# Free-browse exit: left walks off the stack onto the top board.
	nav._enter_element("stack_0")
	await _tick(1)
	await _tap(&"pad_nav_left")
	assert(nav._element == "top_monster_deck",
		"left off the stack should reach the top board: %s" % nav._element)

	# Choice prompt: the cursor jails onto choice_0 and the ring must sit on
	# the button's REAL rect once layout settles, without any cursor move —
	# regression: the ring used to keep the pre-fit rect until the first dpad
	# input (_fit_choice_panel moves the panel a frame after _emit_ctx).
	var opts: Array[String] = ["Ability A", "Ability B"]
	sel._show_choice_selection(0, opts, "Choose which ability to resolve:")
	await _tick(1)
	assert(nav._mode == "choice", "choice ctx did not reach the nav: %s" % nav._mode)
	assert(nav._element == "choice_0", "cursor not jailed onto choice_0: %s" % nav._element)
	await _tick(3) # _fit_choice_panel repositions the panel; the ring must follow
	var btn0: Button = sel._choice_buttons[0]
	var ring := Rect2(nav._cursor.global_position, nav._cursor.size)
	var want: Rect2 = btn0.get_global_rect().grow(nav.CURSOR_PAD)
	assert(ring.position.distance_to(want.position) < 1.0
			and (ring.size - want.size).length() < 1.0,
		"ring not on choice_0's settled rect: ring=%s want=%s" % [ring, want])
	await _shot("02_choice_ring")

	# The jail spans choice <-> stack, and nothing else.
	await _tap(&"pad_nav_up")
	assert(nav._element == "stack_1", "up from choice_0 should reach the bottom stack row: %s" % nav._element)
	await _tap(&"pad_nav_left")
	assert(nav._element == "stack_1", "choice jail let the cursor onto the board")
	await _tap(&"pad_nav_down")
	assert(nav._element == "choice_0", "down did not return to the choice: %s" % nav._element)
	assert(nav.select_toggle_target() == "board", "hint should name the board from the effects area")
	assert(_hint_text(sel._choice_hint_row) == tr("STR_GB_HINT_BOARD"),
		"choice hint row shows '%s'" % _hint_text(sel._choice_hint_row))

	# Select from the choice = read-only board roam: dpad + Y live, A opens
	# the pile/stack viewers (mouse parity), plays / X / B-skip dead, and
	# the choice stays pending throughout.
	await _tap(&"pad_chat")
	assert(nav._choice_roaming, "Select from the choice did not start a roam")
	assert(not nav._in_effects_region(nav._element), "roam left the cursor on the effects area")
	assert(sel._choice_selecting and nav._mode == "choice", "roam disturbed the pending choice")
	assert(nav.select_toggle_target() == "effects", "hint should name the effects area while roaming")
	assert(_hint_text(sel._choice_hint_row) == tr("STR_GB_HINT_EFFECTS"),
		"choice hint row shows '%s' while roaming" % _hint_text(sel._choice_hint_row))
	assert(_hint_text(stack._hint_row) == tr("STR_GB_HINT_EFFECTS"),
		"stack hint row shows '%s' while roaming" % _hint_text(stack._hint_row))
	await _shot("03_roam")
	var roam_origin: String = nav._element
	await _tap(&"pad_nav_right")
	assert(nav._element != roam_origin, "dpad frozen during the roam")

	# A on the discard opens its viewer (mouse parity), the choice stays
	# pending, and the suspend/resume round-trip keeps the roam + cursor.
	nav._enter_element("bot_discard")
	await _tick(1)
	await _tap(&"pad_confirm")
	await _tick(2)
	assert(board.discard_view_overlay.visible, "A on the discard did not open the viewer during the roam")
	assert(sel._choice_selecting and nav._mode == "choice", "discard viewer disturbed the pending choice")
	await _shot("03b_roam_discard_view")
	board.discard_view_overlay.try_close()
	await _tick(2)
	assert(not board.discard_view_overlay.visible, "discard viewer did not close")
	assert(nav._choice_roaming, "roam flag lost across the viewer round-trip")
	assert(nav._element == "bot_discard",
		"cursor did not restore to the discard after the viewer: %s" % nav._element)

	# A on a zone with cards opens the zone stack viewer, same round-trip.
	var roam_player: Variant = board._get_player_state(local_pid)
	if not roam_player.current_monster.is_empty():
		nav._enter_element("bot_z%d" % roam_player.monster_zone)
		await _tick(1)
		await _tap(&"pad_confirm")
		await _tick(2)
		assert(board.zone_stack_view_overlay.visible, "A on the monster zone did not open the stack viewer")
		assert(sel._choice_selecting and nav._mode == "choice", "zone viewer disturbed the pending choice")
		board.zone_stack_view_overlay.try_close()
		await _tick(2)
		assert(nav._choice_roaming, "roam flag lost across the zone-viewer round-trip")

	# Hand cards and End Main stay dead during the roam.
	nav._enter_element("hand_0")
	await _tick(1)
	await _tap(&"pad_confirm")
	assert(sel._choice_selecting and nav._mode == "choice", "A on a hand card during the roam activated something")
	await _tap(&"pad_end_main")
	assert(sel._choice_selecting and nav._mode == "choice", "X during the roam pressed End Main")
	nav._enter_element("bot_discard")
	await _tick(1)

	# B while roaming returns to the choice element left behind...
	await _press_b()
	assert(nav._element == "choice_0", "B did not return the roam to the choice: %s" % nav._element)
	assert(not nav._choice_roaming, "roam flag survived the return")
	assert(sel._choice_selecting, "roam B-return leaked into the prompt ladder")
	# ...while B ON the choice stays refused (mandatory prompt).
	await _press_b()
	assert(sel._choice_selecting and nav._element == "choice_0",
		"B on the choice was not refused")
	await _shot("04_back_on_choice")

	# Stack rebuild under the cursor clamps to the surviving row.
	await _tap(&"pad_nav_up")
	assert(nav._element == "stack_1", "setup: cursor not on the last stack row")
	stack.show_stack([
		{"base_id": "ESD01-016", "label": "Pending A", "player_id": local_pid, "status": "resolving"},
	])
	await _tick(2)
	assert(nav._element == "stack_0", "cursor did not clamp after the rebuild: %s" % nav._element)

	# Cleanup restores free browse; an empty stack relocates the cursor.
	sel._cleanup_choice_selection()
	await _tick(2)
	assert(nav._mode == "none", "choice cleanup did not clear the ctx")
	stack.show_stack([])
	await _tick(2)
	assert(not nav._element.begins_with("stack_"), "cursor stranded on an empty stack")
	assert(nav._cursor.visible, "cursor lost after the stack emptied")

	# With no effects area, Select opens chat again.
	await _tap(&"pad_chat")
	assert(board.chat_input.has_focus(), "Select should open chat with no effects area up")
	var chat_escape := InputEventJoypadButton.new()
	chat_escape.button_index = JOY_BUTTON_DPAD_LEFT
	chat_escape.pressed = true
	Input.parse_input_event(chat_escape)
	await _tick(2)
	chat_escape = InputEventJoypadButton.new()
	chat_escape.button_index = JOY_BUTTON_DPAD_LEFT
	chat_escape.pressed = false
	Input.parse_input_event(chat_escape)
	await _tick(1)
	assert(not board.chat_input.has_focus(), "could not escape chat after the Select regression check")

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
