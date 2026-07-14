extends Node

## Controller navigation tour of the MOBILE layout's chrome — the runtime
## buttons MobileLayout builds have nav ids now:
##   - RIGHT edge column: sys_menu ("...") over sys_turns over the pill stack
##     (cancel/confirm/end main, traversed through while hidden) over the FAB;
##   - LEFT edge column: opponent hand stack over sys_cp over sys_log over
##     sys_view over the local hand stack;
##   - A on sys_log / sys_turns takes the BUMPER path (tray slides in, the
##     cursor enters it, B returns to the toggle);
##   - A on sys_cp toggles the CP tray (cursor stays, ring follows the slide);
##   - A on sys_view cycles the board view;
##   - A on sys_menu opens the "..." popup as a registered modal (vertical
##     focus mesh, B closes on the leading cancel, cursor restored).
##
## Set VERIFY_SHOT_DIR to capture screenshots (headful runs only).
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/GamepadBoardNavMobileTest.tscn

var _settings_mobile_before: bool = false


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


## Walk in one direction until the cursor rests on `target` (hidden pills in
## the lane are traversed through, so the hop count varies with game state).
func _walk_to(nav: Node, action: StringName, target: String, max_steps: int = 8) -> void:
	for i in range(max_steps):
		if nav._element == target:
			return
		var before: String = nav._element
		await _tap(action)
		if nav._element == before:
			break # dead end
	assert(nav._element == target,
		"%s walk stopped on %s, wanted %s" % [action, nav._element, target])


func _ready() -> void:
	# Hermetic bindings: a connected controller loads the USER'S persisted
	# rebinds (user://settings.cfg) — the walk assumes the default map.
	# In-memory only; never touches the saved config.
	GamepadInput._map = GlyphDB.default_map()
	_settings_mobile_before = GameSettings.use_mobile_layout
	GameSettings.use_mobile_layout = true
	await get_tree().process_frame
	var board: Node = load("res://scenes/board/GameBoard.tscn").instantiate()
	get_tree().root.add_child(board)
	await _tick(40) # solo game boot + mobile restyle settle
	assert(board._is_mobile_layout, "board did not apply the mobile layout")
	var mobile: Node = board.get_node("MobileLayout")
	var nav: Node = board.get_node("GamepadBoardNav")

	# Flip to gamepad mode with a synthetic physical press (dpad is inert on
	# takeover, unlike A which could confirm on the resting element).
	await _press_physical(JOY_BUTTON_DPAD_DOWN)
	assert(GamepadHelper.is_using_gamepad(), "joypad press did not enter gamepad mode")
	assert(nav._is_active(), "module inactive with no overlay open")
	assert(nav._cursor != null and nav._cursor.visible, "gamepad mode did not place the cursor")

	# F3 graph overlay on for the whole tour (visual evidence; must not
	# steal input — the desktop suite asserts that separately).
	var debug_overlay: Node = board.get_node_or_null("NavDebugOverlay")
	if debug_overlay and OS.is_debug_build():
		var f3 := InputEventKey.new()
		f3.keycode = KEY_F3
		f3.physical_keycode = KEY_F3
		f3.pressed = true
		Input.parse_input_event(f3)
		await _tick(2)

	nav._enter_element("ap_end_main")
	await _tick(1)
	await _shot("mobile_01_browse_default")

	# --- RIGHT edge column: End Main -> (pills, hidden -> traversed) ->
	# sys_turns -> sys_menu ---
	await _walk_to(nav, &"pad_nav_up", "sys_turns")
	await _tap(&"pad_nav_up")
	assert(nav._element == "sys_menu", "up from sys_turns did not reach sys_menu: %s" % nav._element)

	# --- "..." menu: A opens a registered modal, dpad walks the mesh, B
	# closes on the leading cancel and restores the cursor ---
	await _tap(&"pad_confirm")
	await _tick(3)
	assert(mobile._mobile_menu_open, "A on sys_menu did not open the menu")
	assert(not nav._is_active(), "menu modal did not suspend the board cursor")
	var focus: Control = board.get_viewport().gui_get_focus_owner()
	assert(focus != null and mobile._mobile_menu_panel.is_ancestor_of(focus),
		"menu open did not focus an option button: %s" % str(focus))
	await _shot("mobile_02_menu_open")
	await _press_physical(JOY_BUTTON_DPAD_DOWN)
	await _press_physical(JOY_BUTTON_DPAD_DOWN)
	var focus2: Control = board.get_viewport().gui_get_focus_owner()
	assert(focus2 != null and focus2 != focus and mobile._mobile_menu_panel.is_ancestor_of(focus2),
		"dpad did not walk the menu mesh")
	await _press_physical(JOY_BUTTON_B)
	await _tick(3)
	assert(not mobile._mobile_menu_open, "B did not close the menu")
	assert(nav._is_active(), "menu close did not resume the board cursor")
	assert(nav._element == "sys_menu", "menu close did not restore the cursor: %s" % nav._element)

	# --- sys_turns: A = the RB bumper path (tray slides in, cursor enters
	# the tracker, B returns to the toggle) ---
	await _tap(&"pad_nav_down")
	assert(nav._element == "sys_turns", "down from sys_menu did not reach sys_turns: %s" % nav._element)
	await _tap(&"pad_confirm")
	await _tick(6) # tray tween
	assert(mobile.is_tracker_tray_open(), "A on sys_turns did not open the tracker tray")
	assert(nav._element.begins_with("trk_"), "A on sys_turns did not enter the tracker: %s" % nav._element)
	await _shot("mobile_03_tracker_tray")
	await _press_physical(JOY_BUTTON_B)
	await _tick(6)
	assert(not mobile.is_tracker_tray_open(), "B did not close the tracker tray")
	assert(nav._element == "sys_turns", "B did not return the cursor to sys_turns: %s" % nav._element)

	# --- Cross to the LEFT column: sys_menu sits level with the top row;
	# left enters the opp fan (solo: it exists) or the monster deck, and
	# walking left lands on the opp hand stack — via the fan's left exit or
	# via the playmat row through top_discard, whichever lane the entry
	# element put us on ---
	await _tap(&"pad_nav_up")
	assert(nav._element == "sys_menu", "up did not return to sys_menu: %s" % nav._element)
	await _tap(&"pad_nav_left")
	assert(nav._element.begins_with("opp_hand_") or nav._element == "top_monster_deck",
		"left off sys_menu did not enter the top row: %s" % nav._element)
	for i in range(16):
		if nav._element in ["ap_opp_sort_hand", "ap_opp_hand_toggle"]:
			break
		await _tap(&"pad_nav_left")
	assert(nav._element in ["ap_opp_sort_hand", "ap_opp_hand_toggle"],
		"left walk did not reach the opp hand stack: %s" % nav._element)
	await _tap(&"pad_nav_down")
	assert(nav._element == "sys_cp", "down from the opp stack did not reach sys_cp: %s" % nav._element)

	# --- sys_cp: A toggles the CP tray; the cursor stays on the (sliding)
	# button and the ring follows it ---
	await _tap(&"pad_confirm")
	await _tick(6)
	assert(mobile._mobile_cp_tray_open, "A on sys_cp did not open the CP tray")
	assert(nav._element == "sys_cp", "CP toggle moved the cursor: %s" % nav._element)
	await _shot("mobile_04_cp_tray")
	await _tap(&"pad_confirm")
	await _tick(6)
	assert(not mobile._mobile_cp_tray_open, "second A did not close the CP tray")

	# --- sys_log: A = the LB bumper path ---
	await _tap(&"pad_nav_down")
	assert(nav._element == "sys_log", "down from sys_cp did not reach sys_log: %s" % nav._element)
	await _tap(&"pad_confirm")
	await _tick(6)
	assert(mobile.is_log_tray_open(), "A on sys_log did not open the log tray")
	assert(nav._element == "log_panel", "A on sys_log did not enter the log: %s" % nav._element)
	await _shot("mobile_05_log_tray")
	await _press_physical(JOY_BUTTON_B)
	await _tick(6)
	assert(not mobile.is_log_tray_open(), "B did not close the log tray")
	assert(nav._element == "sys_log", "B did not return the cursor to sys_log: %s" % nav._element)

	# --- sys_view: A cycles the board view ---
	await _tap(&"pad_nav_down")
	assert(nav._element == "sys_view", "down from sys_log did not reach sys_view: %s" % nav._element)
	var view_before: int = mobile._mobile_board_view
	await _tap(&"pad_confirm")
	await _tick(3)
	assert(mobile._mobile_board_view != view_before, "A on sys_view did not cycle the board view")

	# --- Bottom of the left column: the hand stack, then the fan ---
	await _tap(&"pad_nav_down")
	assert(nav._element in ["ap_hand_toggle", "ap_sort_hand"],
		"down from sys_view did not reach the hand stack: %s" % nav._element)
	nav._enter_element("ap_sort_hand")
	await _tick(1)
	await _tap(&"pad_nav_right")
	assert(nav._element.begins_with("hand_"), "right off the sort pill did not enter the fan: %s" % nav._element)

	# --- Fan's right end exits onto the FAB; up climbs the pill stack ---
	var hand_count: int = nav._hand_mgr().managed_cards.size()
	await _walk_to(nav, &"pad_nav_right", "ap_fab_main", hand_count + 2)
	await _shot("mobile_06_fab_from_hand")
	await _tap(&"pad_nav_up")
	assert(nav._element == "ap_end_main", "up from the FAB did not reach End Main: %s" % nav._element)

	print("GAMEPAD_NAV_MOBILE_TEST_PASS")
	GameSettings.use_mobile_layout = _settings_mobile_before
	get_tree().quit(0)
