extends Node

## Controller navigation regression test for the deck builder — drives the
## screen with PHYSICAL joypad events (so the full GamepadInput chain runs:
## logical pad_* plus the mirrored ui_* that Godot's focus traversal uses):
##   - the pointer->gamepad flip wires the mesh and lands on the first pool
##     card without the flipping press activating anything;
##   - the dpad walks the pool grid and exits into the pool header and the
##     filter row; text boxes (search, deck name) are meshed and land idle —
##     A starts editing, the editing escape keeps the cursor on the field;
##   - A adds a pool card (badge-only refresh keeps focus), X removes a copy
##     from the pool side;
##   - LB/RB cycle pool / deck / left panel, remembering the grid spot;
##   - A on the last deck card empties the grid and falls back onto the
##     active tab; X on a stacked deck card removes all copies;
##   - the header band reaches the Max Counter Power button; A opens its
##     dialog as a focus context, the dpad tours the param row and OK, B
##     backs out without leaking into the builder's back handler, and every
##     modal exit (B, dropdown pick, A on OK) restores the cursor to the
##     control that opened it;
##   - B raises the unsaved-changes dialog focused on Cancel, and B again
##     backs out of it.
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/DeckBuilderPadNavTest.tscn

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


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func _is_wrapper(node: Control, grid: GridContainer) -> bool:
	return node != null and node.has_meta(OverlayGridUtil.GRID_CARD_META) \
			and node.get_parent() == grid


func _ready() -> void:
	await get_tree().process_frame
	var builder: Node = load("res://scenes/deck_builder/DeckBuilder.tscn").instantiate()
	get_tree().root.add_child(builder)
	await _tick(5)

	# Wait out the batched pool load.
	var deadline := 600
	while OverlayGridUtil.grid_cards(builder.pool_grid).size() < builder._filtered_pool_cards.size() \
			and deadline > 0:
		await get_tree().process_frame
		deadline -= 1
	assert(deadline > 0, "pool never finished its batched load")
	assert(OverlayGridUtil.grid_cards(builder.pool_grid).size() > 2,
		"filtered pool too small for the walk")

	# Work on the Main tab: adds are type-agnostic there, so the walk is
	# deterministic whatever card sorts first in the pool.
	builder._on_main_tab_pressed()
	await _tick(2)
	assert(builder._get_main_deck_total() == 0, "deck not empty at boot")

	# Flip to gamepad mode with a synthetic physical press. The flipping press
	# must not activate anything (focus is released before the mirrored twin
	# lands), and the flip itself wires the mesh built in pointer mode.
	await _press_button(JOY_BUTTON_A)
	assert(GamepadHelper.is_using_gamepad(), "joypad press did not enter gamepad mode")
	assert(builder._get_main_deck_total() == 0, "the mode-flipping press added a card")
	await _tick(2)

	# Provider lands on the first pool card (deck grid is empty); hints show.
	var w0 := _focus_owner()
	assert(_is_wrapper(w0, builder.pool_grid), "initial focus is not a pool card: %s" % str(w0))
	assert(w0 == OverlayGridUtil.grid_cards(builder.pool_grid)[0], "not the FIRST pool card")
	assert(builder._pad_hint_row.visible, "hint row hidden in gamepad mode")
	assert(builder._pad_hint_row.get_child_count() > 0, "hint row is empty")

	# Grid mesh: right walks the row; up exits into the pool header, then the
	# filter row; two downs re-enter the grid.
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(_focus_owner() == OverlayGridUtil.grid_cards(builder.pool_grid)[1],
		"dpad right did not reach pool card 1: %s" % str(_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_LEFT)
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(builder.pool_zoom_out_button.has_focus(),
		"dpad up did not reach the pool header: %s" % str(_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_UP)
	# The filter row now opens with the search box. Landing must leave it
	# idle (focused, NOT editing) so the dpad keeps navigating.
	assert(builder.search_edit.has_focus(),
		"second dpad up did not reach the search box: %s" % str(_focus_owner()))
	assert(not builder.search_edit.is_editing(),
		"pad focus arrival left the search box editing")
	# A starts editing (where a platform virtual keyboard would pop); the
	# next dpad press escapes IN PLACE — cursor stays on the field — and the
	# one after that moves off it.
	await _press_button(JOY_BUTTON_A)
	assert(builder.search_edit.is_editing(), "A did not start editing the search box")
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(builder.search_edit.has_focus() and not builder.search_edit.is_editing(),
		"editing escape did not keep the cursor on the search box: %s" % str(_focus_owner()))
	# Filter to Battle cards from the pad (right x3, A) — keeps the rest of
	# the walk deterministic: X on a monster-type deck card means "move to
	# monster deck", not "remove all". The refresh rebuilds the pool while
	# chrome holds focus; the toggle must keep it.
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(builder.type_buttons[2].has_focus(),
		"dpad right did not walk the filter row: %s" % str(_focus_owner()))
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(builder.type_buttons[2].button_pressed, "A did not toggle the Battle filter")
	assert(builder.type_buttons[2].has_focus(), "pool refresh stole focus from the filter toggle")
	deadline = 600
	while OverlayGridUtil.grid_cards(builder.pool_grid).size() < builder._filtered_pool_cards.size() \
			and deadline > 0:
		await get_tree().process_frame
		deadline -= 1
	assert(deadline > 0, "filtered pool never finished reloading")

	await _press_button(JOY_BUTTON_DPAD_DOWN)
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(_is_wrapper(_focus_owner(), builder.pool_grid), "dpad down did not re-enter the pool grid")

	# A adds the focused pool card (badge-only refresh — focus must survive).
	var focused_pool := _focus_owner()
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(builder._get_main_deck_total() == 1, "A did not add the pool card")
	assert(_focus_owner() == focused_pool, "adding rebuilt the pool under the cursor")
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(builder._get_main_deck_total() == 2, "second A did not add another copy")

	# X on the pool card removes one copy without leaving the pool.
	await _press_button(JOY_BUTTON_X)
	await _tick(2)
	assert(builder._get_main_deck_total() == 1, "X did not remove a copy from the pool side")
	assert(_focus_owner() == focused_pool, "pool X moved focus")

	# LB jumps pool -> deck; the lone deck card holds focus.
	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	await _tick(2)
	assert(_is_wrapper(_focus_owner(), builder.deck_grid),
		"LB did not land in the deck grid: %s" % str(_focus_owner()))

	# A removes the last copy; the emptied grid falls back onto the active tab.
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(builder._get_main_deck_total() == 0, "A did not remove the deck card")
	assert(builder.main_tab_button.has_focus(),
		"emptied deck grid did not fall back to the active tab: %s" % str(_focus_owner()))

	# LB again reaches the left panel; dpad-right crosses back into the deck
	# header (row wrap first, then the pinned exit on the row's last control).
	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	await _tick(2)
	var picker: Control = builder.deck_list_view.pad_focus_targets()[0]
	assert(picker.has_focus(), "LB from the deck did not reach the left panel: %s" % str(_focus_owner()))
	# The deck-name box sits above the picker in the left stack and lands
	# idle like every meshed text field.
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(builder.deck_name_edit.has_focus(),
		"dpad up did not reach the deck-name box: %s" % str(_focus_owner()))
	assert(not builder.deck_name_edit.is_editing(),
		"pad focus arrival left the deck-name box editing")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(picker.has_focus(),
		"dpad down did not return to the picker: %s" % str(_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(builder.monster_tab_button.has_focus(),
		"left panel dpad-right did not cross into the deck header: %s" % str(_focus_owner()))

	# RB from the deck header returns to the pool at the remembered card.
	await _press_button(JOY_BUTTON_RIGHT_SHOULDER)
	await _tick(2)
	assert(_focus_owner() == focused_pool,
		"RB did not restore the remembered pool spot: %s" % str(_focus_owner()))

	# Re-add two copies, jump to the deck, and remove ALL with X.
	await _press_button(JOY_BUTTON_A)
	await _press_button(JOY_BUTTON_A)
	await _tick(2)
	assert(builder._get_main_deck_total() == 2, "re-adds failed")
	await _press_button(JOY_BUTTON_LEFT_SHOULDER)
	await _tick(2)
	assert(_is_wrapper(_focus_owner(), builder.deck_grid), "LB back into the deck failed")
	await _press_button(JOY_BUTTON_X)
	await _tick(3)
	assert(builder._get_main_deck_total() == 0, "deck X did not remove all copies")

	# The emptied grid fell back onto the active tab; dpad-right walks the
	# header band to the Max Counter Power button (zoom -, zoom +, Max CP).
	assert(builder.main_tab_button.has_focus(), "emptied deck did not fall back to the tab")
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(builder.max_cp_button.has_focus(),
		"dpad right did not reach the Max CP button: %s" % str(_focus_owner()))
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(builder.max_counter_dialog.visible, "A did not open the Max CP dialog")
	assert(GamepadHelper.is_top_context(builder.max_counter_dialog),
		"Max CP dialog did not take the focus context")
	assert(builder.max_counter_dialog.borderless,
		"Max CP dialog is not a fixed borderless window")

	# Inside the dialog (its own viewport — root _focus_owner() can't see it):
	# the provider lands on OK; up enters the param row, right walks it, down
	# returns to OK. The card previews are FOCUS_NONE and every wired control
	# pins all four directions, so the walk can never touch them.
	var max_cp_ok: Button = builder.max_counter_dialog.get_ok_button()
	assert(GamepadHelper.gui_focus_owner() == max_cp_ok,
		"Max CP dialog focus not on OK: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(GamepadHelper.gui_focus_owner() == builder.max_counter_dialog._zone_option,
		"dpad up did not enter the param row: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(GamepadHelper.gui_focus_owner() == builder.max_counter_dialog._opp_zone_option,
		"dpad right did not walk the param row: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(GamepadHelper.gui_focus_owner() == builder.max_counter_dialog._rage_option,
		"dpad right did not reach the rage option: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(GamepadHelper.gui_focus_owner() == max_cp_ok,
		"dpad down did not return to OK: %s" % str(GamepadHelper.gui_focus_owner()))

	# B closes the dialog from anywhere inside it. The handler reacts to the
	# TRAILING ui_cancel twin, so the press must not leak into the builder's
	# back handler (which would raise the unsaved gate on top of the close).
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(not builder.max_counter_dialog.visible, "B did not close the Max CP dialog")
	assert(not builder.unsaved_dialog.visible,
		"the B that closed the Max CP dialog leaked into the back handler")
	assert(GamepadHelper.is_top_context(builder),
		"B close did not return the focus context to the builder")
	# The pop restores the control that opened the modal — the cursor stays
	# where the user left it instead of jumping to the builder's default.
	assert(builder.max_cp_button.has_focus(),
		"B close did not restore the cursor to the Max CP button: %s" % str(_focus_owner()))

	# Reopen to exercise the dropdown and A-on-OK close paths as well.
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(builder.max_counter_dialog.visible, "A did not reopen the Max CP dialog")
	assert(GamepadHelper.gui_focus_owner() == max_cp_ok,
		"reopened dialog focus not on OK: %s" % str(GamepadHelper.gui_focus_owner()))

	# Dropdown popups are focus contexts too: picking an item must return the
	# cursor to the OptionButton, not yank it to the dialog's OK default.
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(GamepadHelper.gui_focus_owner() == builder.max_counter_dialog._zone_option,
		"dpad up did not re-enter the param row: %s" % str(GamepadHelper.gui_focus_owner()))
	var zone_popup: PopupMenu = builder.max_counter_dialog._zone_option.get_popup()
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(zone_popup.visible, "A did not open the zone dropdown")
	assert(GamepadHelper.is_top_context(zone_popup),
		"the zone dropdown did not take the focus context")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(not zone_popup.visible, "A did not pick a dropdown item")
	assert(GamepadHelper.gui_focus_owner() == builder.max_counter_dialog._zone_option,
		"the dropdown close did not restore the zone OptionButton: %s"
			% str(GamepadHelper.gui_focus_owner()))

	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(GamepadHelper.gui_focus_owner() == max_cp_ok,
		"dpad down from the zone option did not reach OK: %s"
			% str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(not builder.max_counter_dialog.visible, "A on OK did not close the Max CP dialog")
	assert(GamepadHelper.is_top_context(builder),
		"closing the Max CP dialog did not return the focus context to the builder")
	assert(builder.max_cp_button.has_focus(),
		"the OK close did not restore the cursor to the Max CP button: %s" % str(_focus_owner()))

	# B raises the unsaved-changes gate; the modal lands on Cancel (never the
	# destructive Discard). A on the focused Cancel closes it — exercising
	# the window_input forwarding: a focused embedded Window swallows joypad
	# input before the root translators run, so without the register_modal
	# forwarding the pad would be dead inside every dialog. (B relies on
	# close_on_escape, which only reacts to real key events — not the
	# mirrored ui_cancel action — so A-on-Cancel is the canonical pad path.)
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(builder.unsaved_dialog.visible, "B did not raise the unsaved dialog")
	assert(GamepadHelper.is_top_context(builder.unsaved_dialog),
		"dialog did not take the focus context")
	assert(GamepadHelper.gui_focus_owner() == builder.unsaved_dialog.get_cancel_button(),
		"dialog focus not on Cancel: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_A)
	await _tick(3)
	assert(not builder.unsaved_dialog.visible, "A on the focused Cancel did not close the dialog")
	assert(is_instance_valid(builder) and builder.is_inside_tree(),
		"canceling the dialog still left the deck builder")

	print("DECK_BUILDER_PAD_NAV_TEST_PASS")
	get_tree().quit(0)
