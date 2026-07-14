extends GdUnitTestSuite

## Controller support for the Extras screen's popups: every list/dialog popup
## is a registered focus context, its buttons are dpad-meshed (rows re-mesh
## on rebuild), and pad B closes on the LEADING pad_cancel — the mirrored
## ui_cancel twin is stamped as spent so it can't leak into the screen
## underneath. Destructive row buttons are never pressed here (they operate
## on the real replay/save directories).

const MODAL_META := &"_gamepad_modal"

var _extras: Control


func before_test() -> void:
	GamepadHelper._cancel_swallow_frame = -100  # no stale twin swallow
	_extras = auto_free(load("res://scenes/menus/Extras.tscn").instantiate())
	add_child(_extras)


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


func _fake_saves(count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in range(count):
		entries.append({
			"path": "user://fake_save_%d.json" % i,
			"player_names": ["Alice", "Bob"],
			"turn_number": i + 1,
			"timestamp": "2026-01-01 00:0%d" % i,
			"mode": "solo",
			"label": "",
			"game_version": "",
			"deck_names": ["DeckA", "DeckB"],
			"is_favorite": false,
		})
	return entries


func _last_popup() -> PopupPanel:
	var popup: PopupPanel = null
	for child in _extras.get_children():
		if child is PopupPanel:
			popup = child
	assert_object(popup).override_failure_message("no popup opened").is_not_null()
	return popup


func _assert_buttons_meshed(root: Node) -> void:
	for control: Control in root.find_children("*", "Button", true, false):
		assert_bool(GamepadHelper.has_focus_neighbors(control)) \
			.override_failure_message("unmeshed Button: %s" % control.text).is_true()


func _press_pad_cancel(popup: PopupPanel) -> void:
	# The LEADING pad_cancel closes; emit the mirrored ui_cancel twin too and
	# rely on the swallow stamp to make it a no-op (a real press sends both).
	var lead := InputEventAction.new()
	lead.action = &"pad_cancel"
	lead.pressed = true
	popup.window_input.emit(lead)
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	popup.window_input.emit(twin)


func test_replay_list_is_meshed_modal_and_pad_closable() -> void:
	_extras._show_replay_list(_fake_replays(3))
	var popup := _last_popup()
	assert_bool(popup.has_meta(MODAL_META)) \
		.override_failure_message("replay list is not a registered modal").is_true()
	_assert_buttons_meshed(popup)
	_press_pad_cancel(popup)
	assert_bool(popup.visible) \
		.override_failure_message("leading pad_cancel did not close the list").is_false()


func test_replay_list_rows_stay_meshed_after_repopulate() -> void:
	_extras._show_replay_list(_fake_replays(3))
	var popup := _last_popup()
	# Filter-style repopulate frees every row and builds fresh ones.
	_extras._populate_replay_list(_fake_replays(2))
	await await_idle_frame()
	_assert_buttons_meshed(popup)


func test_save_list_is_meshed_modal_and_pad_closable() -> void:
	_extras._show_save_list(_fake_saves(2))
	var popup := _last_popup()
	assert_bool(popup.has_meta(MODAL_META)).is_true()
	_assert_buttons_meshed(popup)
	_press_pad_cancel(popup)
	assert_bool(popup.visible).is_false()


func test_confirm_dialog_pad_close_does_not_confirm() -> void:
	var confirmed := [false]
	_extras._show_confirm("really?", func(): confirmed[0] = true)
	var popup := _last_popup()
	_assert_buttons_meshed(popup)
	_press_pad_cancel(popup)
	assert_bool(popup.visible) \
		.override_failure_message("B did not close the confirm dialog").is_false()
	assert_bool(confirmed[0]) \
		.override_failure_message("pad B must never trigger the destructive confirm").is_false()


func test_label_dialog_line_edit_is_meshed() -> void:
	_extras._show_label_dialog("user://fake_replay_0.zst", "")
	var popup := _last_popup()
	var line_edit: LineEdit = popup.find_children("*", "LineEdit", true, false)[0]
	assert_bool(GamepadHelper.has_focus_neighbors(line_edit)) \
		.override_failure_message("label dialog LineEdit is not meshed").is_true()
	_assert_buttons_meshed(popup)
	# While the field is EDITING, B must escape the field, not close the
	# dialog (the pointer-mode grab_focus above left it editing).
	_press_pad_cancel(popup)
	assert_bool(popup.visible) \
		.override_failure_message("B closed the dialog over an editing field").is_true()
	line_edit.unedit()  # pad landings are idle (fence); now B closes
	GamepadHelper._cancel_swallow_frame = -100  # fresh press
	_press_pad_cancel(popup)
	assert_bool(popup.visible).is_false()


func test_player_choice_dialog_is_meshed_and_pad_closable() -> void:
	_extras._show_player_choice_dialog(["Alice", "Bob"], func(_id: int): pass)
	var popup := _last_popup()
	assert_bool(popup.has_meta(MODAL_META)).is_true()
	_assert_buttons_meshed(popup)
	_press_pad_cancel(popup)
	assert_bool(popup.visible).is_false()


func test_game_log_list_is_meshed_and_pad_close_frees_it() -> void:
	var logs: Array[Dictionary] = [
		{"filename": "game_1.txt", "modified_unix": 0, "path": "user://fake_log.txt"},
	]
	_extras._show_game_log_list(logs)
	var popup := _last_popup()
	assert_bool(popup.has_meta(MODAL_META)).is_true()
	_assert_buttons_meshed(popup)
	_press_pad_cancel(popup)
	assert_bool(popup.visible).is_false()
	# B matches Cancel exactly: the log list frees itself on close.
	assert_bool(popup.is_queued_for_deletion()) \
		.override_failure_message("B must free the log list like Cancel does").is_true()


func test_open_folder_prompts_nested_confirm_without_closing_list() -> void:
	var opened: Array = []
	ExternalConfirm._shell_open = func(target: String) -> void: opened.append(target)
	_extras._show_replay_list(_fake_replays(1))
	var popup := _last_popup()
	var open_folder_btn: Button = null
	for control: Button in popup.find_children("*", "Button", true, false):
		if control.text == tr("STR_EXTRAS_OPEN_FOLDER"):
			open_folder_btn = control
	assert_object(open_folder_btn).is_not_null()
	open_folder_btn.pressed.emit()
	# Nothing opens yet; the confirm nests as a CHILD window of the list popup
	# (a sibling exclusive window would be rejected).
	assert_array(opened) \
		.override_failure_message("folder opened without confirmation").is_empty()
	var dialog: ConfirmationDialog = null
	for child in popup.get_children():
		if child is ConfirmationDialog:
			dialog = child
	assert_object(dialog) \
		.override_failure_message("confirm dialog is not a child of the list popup").is_not_null()
	# B closes the confirm only — its swallowed twins must not leak into the
	# list popup underneath.
	var lead := InputEventAction.new()
	lead.action = &"pad_cancel"
	lead.pressed = true
	dialog.window_input.emit(lead)
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	popup.window_input.emit(twin)
	assert_bool(dialog.visible) \
		.override_failure_message("B did not close the confirm dialog").is_false()
	assert_bool(popup.visible) \
		.override_failure_message("closing the confirm must not close the list popup").is_true()
	assert_array(opened).is_empty()
	ExternalConfirm._shell_open = Callable(OS, "shell_open")
