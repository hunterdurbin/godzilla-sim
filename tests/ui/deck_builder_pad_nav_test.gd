extends Node

## Controller navigation regression test for the deck builder — drives the
## screen with PHYSICAL joypad events (so the full GamepadInput chain runs:
## logical pad_* plus the mirrored ui_* that Godot's focus traversal uses):
##   - the pointer->gamepad flip wires the mesh and lands on the first pool
##     card without the flipping press activating anything;
##   - the dpad walks the pool grid and exits into the pool header and the
##     filter row;
##   - A adds a pool card (badge-only refresh keeps focus), X removes a copy
##     from the pool side;
##   - LB/RB cycle pool / deck / left panel, remembering the grid spot;
##   - A on the last deck card empties the grid and falls back onto the
##     active tab; X on a stacked deck card removes all copies;
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
	assert(builder.type_buttons[0].has_focus(),
		"second dpad up did not reach the filter row: %s" % str(_focus_owner()))
	# Filter to Battle cards from the pad (right x2, A) — keeps the rest of
	# the walk deterministic: X on a monster-type deck card means "move to
	# monster deck", not "remove all". The refresh rebuilds the pool while
	# chrome holds focus; the toggle must keep it.
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
