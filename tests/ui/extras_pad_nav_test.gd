extends Node

## Controller navigation regression test for the Extras menu — drives the
## screen with PHYSICAL joypad events (so the full GamepadInput chain runs:
## logical pad_* plus the mirrored ui_* that Godot's focus traversal uses):
##   - the pointer->gamepad flip lands on Watch Replay without the flipping
##     press activating anything; the dpad walks all five menu buttons;
##   - the replay list opens as a focus context landing on the first row's
##     info button; ←/→ wraps within a row (star/info/label/delete), ↑/↓
##     changes rows at the clamped column and reaches the toolbar and Cancel;
##     B closes on the leading pad_cancel and restores the opener focus;
##   - the confirm dialog lands on Cancel (never the destructive Confirm) and
##     B closes it without firing the callback;
##   - the label dialog lands on Cancel with its meshed LineEdit idle; A
##     starts editing, the editing escape keeps the cursor on the field, B
##     closes.
## Destructive row buttons are never pressed (real replay/save directories).
##
## Run:
##   godot --headless --quit-after 3000 res://tests/ui/ExtrasPadNavTest.tscn

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


func _fake_replays(count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in range(count):
		entries.append({
			"path": "user://fake_replay_%d.zst" % i,
			"player_names": ["Alice", "Bob"],
			"winner_id": 0,
			"turns": 3 + i,
			"timestamp": "2026-01-01 00:0%d" % i,
			"deck_names": ["DeckA", "DeckB"],
			"label": "",
			"game_version": "",
			"is_favorite": false,
		})
	return entries


func _last_popup(extras: Control) -> PopupPanel:
	var popup: PopupPanel = null
	for child in extras.get_children():
		if child is PopupPanel:
			popup = child
	assert(popup != null, "no popup opened")
	return popup


func _row_button(extras: Control, row_idx: int, col: int) -> Button:
	var row: Node = extras._replay_list_vbox.get_children()[row_idx]
	var buttons: Array[Control] = extras._row_buttons(row)
	return buttons[col]


func _ready() -> void:
	# Hermetic bindings: a connected controller loads the USER'S persisted
	# rebinds (user://settings.cfg) — the walk assumes the default map.
	# In-memory only; never touches the saved config.
	GamepadInput._map = GlyphDB.default_map()
	await get_tree().process_frame
	var extras: Control = load("res://scenes/menus/Extras.tscn").instantiate()
	get_tree().root.add_child(extras)
	await _tick(5)

	# Flip to gamepad mode with a synthetic physical press. The flipping press
	# must not activate anything (focus is released before the mirrored twin
	# lands).
	await _press_button(JOY_BUTTON_A)
	assert(GamepadHelper.is_using_gamepad(), "joypad press did not enter gamepad mode")
	for child in extras.get_children():
		assert(not (child is PopupPanel and (child as PopupPanel).visible),
			"the mode-flipping press opened a popup")
	await _tick(2)
	assert(extras.watch_replay_button.has_focus(),
		"provider did not land on Watch Replay: %s" % str(get_viewport().gui_get_focus_owner()))

	# The plain VBox relies on geometric traversal: down walks all five buttons.
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(extras.load_game_button.has_focus(), "dpad down did not reach Load Game")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(extras.load_game_online_button.has_focus(), "dpad down did not reach Load Game Online")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(extras.game_logs_button.has_focus(), "dpad down did not reach Game Logs")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(extras.back_button.has_focus(), "dpad down did not reach Back")

	# Replay list: modal context, provider lands on the first row's INFO button.
	extras._show_replay_list(_fake_replays(3))
	await _tick(4)
	var list_popup := _last_popup(extras)
	assert(list_popup.visible, "replay list did not open")
	assert(GamepadHelper.is_top_context(list_popup), "replay list did not take the focus context")
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 0, 1),
		"list focus not on the first row's info button: %s" % str(GamepadHelper.gui_focus_owner()))

	# Row mesh: right walks star/info/label/delete with wrap; down changes rows
	# at the clamped column; up from the first row reaches the toolbar.
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 0, 2),
		"dpad right did not reach the label button")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 1, 2),
		"dpad down did not keep the column on the next row")
	await _press_button(JOY_BUTTON_DPAD_LEFT)
	await _press_button(JOY_BUTTON_DPAD_LEFT)
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 1, 0),
		"dpad left did not walk back to the star button")
	await _press_button(JOY_BUTTON_DPAD_LEFT)
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 1, 3),
		"dpad left did not wrap to the delete button")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(extras._replay_cancel.has_focus(),
		"dpad down past the last row did not reach Cancel: %s" % str(GamepadHelper.gui_focus_owner()))
	# Cancel is a one-button band: up re-enters the last row at its column 0.
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(GamepadHelper.gui_focus_owner() == _row_button(extras, 2, 0),
		"dpad up from Cancel did not re-enter the last row")

	# B closes on the leading pad_cancel; the mirrored twin is swallowed so it
	# can't leak into the screen's back handler (which would change scene to
	# the main menu), and the pop restores the opener focus (Back held it).
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(not list_popup.visible, "B did not close the replay list")
	assert(is_instance_valid(extras) and extras.is_inside_tree(),
		"the B that closed the list leaked into the Extras back handler")
	assert(GamepadHelper.is_top_context(extras), "close did not return the context to Extras")
	assert(extras.back_button.has_focus(),
		"close did not restore the opener focus: %s" % str(get_viewport().gui_get_focus_owner()))

	# Confirm dialog: lands on Cancel, B closes without confirming.
	var confirmed := [false]
	extras._show_confirm("really?", func(): confirmed[0] = true)
	await _tick(4)
	var confirm_popup := _last_popup(extras)
	var confirm_cancel: Button = confirm_popup.find_children("*", "Button", true, false)[0]
	assert(GamepadHelper.gui_focus_owner() == confirm_cancel,
		"confirm dialog focus not on Cancel: %s" % str(GamepadHelper.gui_focus_owner()))
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(not confirm_popup.visible, "B did not close the confirm dialog")
	assert(not confirmed[0], "pad B fired the destructive confirm callback")

	# Label dialog: pad lands on Cancel; the meshed LineEdit sits idle above —
	# A starts editing, the editing escape keeps the cursor on the field.
	extras._show_label_dialog("user://fake_replay_0.zst", "")
	await _tick(4)
	var label_popup := _last_popup(extras)
	var line_edit: LineEdit = label_popup.find_children("*", "LineEdit", true, false)[0]
	var label_cancel: Button = label_popup.find_children("*", "Button", true, false)[0]
	assert(GamepadHelper.gui_focus_owner() == label_cancel,
		"label dialog focus not on Cancel: %s" % str(GamepadHelper.gui_focus_owner()))
	assert(not line_edit.is_editing(), "the label field started editing on open")
	await _press_button(JOY_BUTTON_DPAD_UP)
	assert(GamepadHelper.gui_focus_owner() == line_edit,
		"dpad up did not reach the label field: %s" % str(GamepadHelper.gui_focus_owner()))
	assert(not line_edit.is_editing(), "pad focus arrival left the label field editing")
	await _press_button(JOY_BUTTON_A)
	assert(line_edit.is_editing(), "A did not start editing the label field")
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert(line_edit.has_focus() and not line_edit.is_editing(),
		"editing escape did not keep the cursor on the label field")
	await _press_button(JOY_BUTTON_B)
	await _tick(3)
	assert(not label_popup.visible, "B did not close the label dialog")
	assert(GamepadHelper.is_top_context(extras),
		"closing the label dialog did not return the context to Extras")

	print("EXTRAS_PAD_NAV_TEST_PASS")
	get_tree().quit(0)
