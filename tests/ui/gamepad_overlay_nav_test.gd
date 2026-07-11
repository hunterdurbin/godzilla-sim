extends Node

## Controller overlay-navigation regression test — every in-game modal is
## pad-drivable. Boots a solo GameBoard, flips to gamepad mode, then drives
## the overlays with PHYSICAL joypad events (so the full GamepadInput chain
## runs: logical pad_* + the mirrored ui_* that Godot's focus traversal and
## the board's cancel ladder listen for):
##   - card-grid viewer: register_modal focuses the first card, the grid
##     meshes into the chrome (dpad reaches Close), A closes, the board
##     cursor resumes with no residual focus;
##   - deck search: grid -> toggle row, toggling Stacked keeps focus, B
##     skips; View Board minimizes (context pops, board cursor resumes,
##     chip shows) and B restores with focus back in the grid;
##   - card zoom over a grid: dpad is swallowed (grid focus can't crawl
##     behind the zoom), B closes the zoom only;
##   - card select: A moves pool -> selection, cross-links reach the
##     selection grid, removing the last pick returns to the pool, Confirm
##     resolves;
##   - deck arrange: A toggles a card between Keep and Discard, RB/LB
##     reorder within Keep, Confirm resolves keep+discard.
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/GamepadOverlayNavTest.tscn

func _tick(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _press_button(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await _tick(3)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _tick(2)


func _focus_owner(board: Node) -> Control:
	return board.get_viewport().gui_get_focus_owner()


func _assert_no_focus(board: Node, context: String) -> void:
	assert(_focus_owner(board) == null,
		"real focus held on the board (%s): %s" % [context, str(_focus_owner(board))])


func _is_grid_card(node: Control) -> bool:
	return node != null and node.has_signal("card_clicked")


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
	var nav: Node = board.get_node("GamepadBoardNav")
	_assert_no_focus(board, "gamepad takeover")

	# Sample card dicts from the dealt hand.
	var hand: CardManager = board.player1_hand
	assert(hand.managed_cards.size() >= 3, "solo boot dealt fewer than 3 cards")
	var dicts: Array = []
	for card in hand.managed_cards:
		dicts.append(card.card_data)

	# --- Card-grid viewer: modal focus, grid -> chrome, A closes ------------
	var viewer: Node = board.discard_view_overlay
	viewer.show_cards([dicts[0], dicts[1], dicts[2]], "test discard")
	await _tick(2)
	assert(not nav._is_active(), "board cursor still active under the viewer")
	assert(GamepadHelper.is_top_context(viewer), "viewer did not take the focus context")
	assert(_is_grid_card(_focus_owner(board)), "first grid card not focused: %s" % str(_focus_owner(board)))

	# Single row of 3 (stacked view may group, but never grows rows): one
	# dpad-down exits the grid into the bottom chrome. View Board is hidden
	# for passive views, so Close is the visible chrome stop.
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(viewer._close.has_focus(), "dpad down did not reach Close: %s" % str(_focus_owner(board)))
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(not viewer.visible, "A on Close did not close the viewer")
	assert(nav._is_active(), "board cursor did not resume after the viewer closed")
	_assert_no_focus(board, "after viewer close")

	# --- Deck search: chrome toggle keeps focus, zoom swallows dpad, B skips,
	# View Board minimize + B restore round-trip --------------------------------
	var search: Node = board.deck_search_overlay
	var search_result: Array = [null]
	var search_cb := func(picked: Dictionary) -> void: search_result[0] = picked
	search.show_prompt([dicts[0], dicts[1]], dicts, "test search", true, search_cb)
	await _tick(2)
	assert(GamepadHelper.is_top_context(search), "deck search did not take the focus context")
	assert(_is_grid_card(_focus_owner(board)), "deck search first card not focused")

	# Up from the top row lands on the toggle row (ShowAll is chrome[0]).
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(search._show_all.has_focus(), "dpad up did not reach the toggle row: %s" % str(_focus_owner(board)))
	var show_all_before: bool = search._show_all.button_pressed
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(search._show_all.button_pressed != show_all_before, "A did not flip the ShowAll toggle")
	assert(search._show_all.has_focus(), "grid rebuild stole focus from the toggle that caused it")
	await _press_button(JOY_BUTTON_A) # flip back
	await _tick(2)

	# Back into the grid, zoom the focused card with Y: while the zoom is up,
	# dpad must NOT crawl the grid mesh behind it.
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	var zoom_card: Control = _focus_owner(board)
	assert(_is_grid_card(zoom_card), "dpad down did not re-enter the grid")
	await _press_button(JOY_BUTTON_Y)
	await _tick(2)
	var zoom: Node = board.card_zoom_overlay
	assert(zoom.visible, "Y on a focused card did not open the zoom")
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(_focus_owner(board) == zoom_card, "dpad leaked through the zoom into the grid mesh")
	await _press_button(JOY_BUTTON_B)
	await _tick(2)
	assert(not zoom.visible, "B did not close the zoom")
	assert(search.visible, "closing the zoom closed the deck search too")
	assert(_focus_owner(board) == zoom_card, "grid focus lost across the zoom round-trip")

	# View Board minimizes: context pops, board cursor resumes, chip shows.
	search._on_view_board()
	await _tick(2)
	assert(not search.visible, "View Board did not hide the overlay")
	assert(board._minimize_chip.visible, "minimize chip not shown")
	assert(nav._is_active(), "board cursor did not resume while minimized")
	assert(GamepadHelper.is_top_context(board), "board not top context while minimized")

	# B restores the minimized overlay and re-focuses the grid.
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(search.visible, "B did not restore the minimized overlay")
	assert(not board._minimize_chip.visible, "chip still visible after restore")
	assert(_is_grid_card(_focus_owner(board)), "restore did not re-focus the grid")

	# B again skips (allow_skip) and resolves with {}.
	await _press_button(JOY_BUTTON_B)
	await _tick(2)
	assert(not search.visible, "B did not skip the deck search")
	assert(search_result[0] != null and (search_result[0] as Dictionary).is_empty(),
		"skip did not resolve with an empty pick")
	assert(nav._is_active(), "board cursor did not resume after skip")
	_assert_no_focus(board, "after deck search skip")

	# --- Card select: A picks, cross-link reaches the selection, A unpicks,
	# Confirm resolves ----------------------------------------------------------
	var select: Node = board.card_pool_select_overlay
	var select_result: Array = [null]
	var select_cb := func(picked: Array) -> void: select_result[0] = picked
	select.show_prompt([dicts[0], dicts[1]], dicts, "test select", 1, 2, select_cb)
	await _tick(2)
	assert(_is_grid_card(_focus_owner(board)), "card select first pool card not focused")

	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(select._selected.size() == 1, "A did not pick the focused pool card")
	assert(_is_grid_card(_focus_owner(board)), "pick did not keep focus in the pool grid")

	# The pool shrank to one card; right crosses into the selection grid.
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	var sel_card: Control = _focus_owner(board)
	assert(_is_grid_card(sel_card), "right did not reach the selection grid")
	assert(OverlayGridUtil.grid_cards(select._selection_grid).has(sel_card),
		"focus owner is not a selection-grid card")
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(select._selected.is_empty(), "A did not unpick the selection card")
	assert(OverlayGridUtil.grid_cards(select._pool_grid).has(_focus_owner(board)),
		"emptying the selection did not return focus to the pool")

	# Re-pick, then walk down to the button row and confirm.
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(select._selected.size() == 1, "re-pick failed")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(select._skip.has_focus(), "dpad down did not reach the button row: %s" % str(_focus_owner(board)))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(select._confirm.has_focus(), "right did not reach Confirm")
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(not select.visible, "Confirm did not close the card select")
	assert(select_result[0] != null and (select_result[0] as Array).size() == 1,
		"confirm did not resolve with the picked card")
	_assert_no_focus(board, "after card select confirm")

	# --- Deck arrange: A toggles piles, RB/LB reorder Keep, Confirm resolves ---
	var arrange: Node = board.deck_arrange_overlay
	var arrange_result: Array = [null, null]
	var arrange_cb := func(keep: Array, discard: Array) -> void:
		arrange_result[0] = keep
		arrange_result[1] = discard
	arrange.show_prompt([dicts[0], dicts[1], dicts[2]], "test arrange", arrange_cb)
	await _tick(2)
	assert(_is_grid_card(_focus_owner(board)), "deck arrange first Keep card not focused")
	var first_id: String = arrange._keep[0].get("id", "")
	var second_id: String = arrange._keep[1].get("id", "")

	# A sends Keep[0] to Discard; focus stays on the Keep pile.
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(arrange._keep.size() == 2 and arrange._discard.size() == 1,
		"A did not move the focused card to Discard")
	assert(arrange._discard[0].get("id", "") == first_id, "wrong card moved to Discard")
	assert(OverlayGridUtil.grid_cards(arrange._keep_cards).has(_focus_owner(board)),
		"toggle did not keep focus in the Keep grid")

	# RB shifts the focused Keep card right; focus follows it.
	await _press_button(JOY_BUTTON_RIGHT_SHOULDER)
	await _tick(2)
	assert(arrange._keep[1].get("id", "") == second_id,
		"RB did not shift the Keep card right: %s" % str(arrange._keep))
	assert(OverlayGridUtil.focused_index(arrange._keep_cards) == 1, "focus did not follow the shifted card")
	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	await _tick(2)
	assert(arrange._keep[0].get("id", "") == second_id, "LB did not shift the card back")
	assert(OverlayGridUtil.focused_index(arrange._keep_cards) == 0, "focus did not follow the LB shift")

	# Walk down to the button row (ViewBoard, Confirm) and confirm.
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(arrange._view_board.has_focus(), "dpad down did not reach the arrange button row: %s" % str(_focus_owner(board)))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(arrange._confirm.has_focus(), "right did not reach the arrange Confirm")
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(not arrange.visible, "Confirm did not close the deck arrange")
	assert((arrange_result[0] as Array).size() == 2 and (arrange_result[1] as Array).size() == 1,
		"arrange did not resolve keep=2 / discard=1: %s / %s" % [str(arrange_result[0]), str(arrange_result[1])])
	assert(nav._is_active(), "board cursor did not resume after the arrange")
	_assert_no_focus(board, "after deck arrange confirm")

	print("GAMEPAD_OVERLAY_NAV_TEST_PASS")
	get_tree().quit(0)
