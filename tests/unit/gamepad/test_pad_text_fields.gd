extends GdUnitTestSuite

## Pad-navigable text boxes: meshed LineEdits (focus_neighbor wired) hold
## pad focus while idle — GamepadHelper unedits them the moment navigation
## lands (no virtual-keyboard pop on pass-through), A starts editing
## deliberately, and the editing escape (dpad/B/select) unedits in place so
## the cursor stays on the field. Unmeshed fields (board chat, dialog
## inputs) keep the old focus-means-typing behavior.

var _was_gamepad: bool


func before_test() -> void:
	_was_gamepad = GamepadHelper._using_gamepad
	GamepadHelper._using_gamepad = true


func after_test() -> void:
	GamepadHelper._using_gamepad = _was_gamepad


func _add_line_edit(meshed: bool) -> LineEdit:
	var field := LineEdit.new()
	add_child(field)
	if meshed:
		field.focus_neighbor_right = field.get_path_to(field)
	return auto_free(field) as LineEdit


func test_fence_only_while_editing() -> void:
	var field := _add_line_edit(true)
	field.grab_focus()
	field.unedit()
	assert_bool(GamepadInput._is_text_editing()) \
		.override_failure_message("idle focused LineEdit must not fence the pad").is_false()
	field.edit()
	assert_bool(GamepadInput._is_text_editing()) \
		.override_failure_message("editing LineEdit must fence the pad").is_true()


func test_pad_focus_arrival_unedits_meshed_field() -> void:
	var field := _add_line_edit(true)
	field.grab_focus()  # Godot enters edit mode with the focus grab
	await await_idle_frame()
	assert_bool(field.has_focus()).is_true()
	assert_bool(field.is_editing()) \
		.override_failure_message("pad focus arrival left a meshed field editing").is_false()


func test_pad_focus_arrival_keeps_unmeshed_field_editing() -> void:
	var field := _add_line_edit(false)
	field.grab_focus()  # e.g. the board chat toggle: focus means typing
	await await_idle_frame()
	assert_bool(field.is_editing()) \
		.override_failure_message("unmeshed field lost its focus-means-typing behavior").is_true()


func test_escape_unedits_meshed_field_in_place() -> void:
	var field := _add_line_edit(true)
	field.grab_focus()
	field.edit()
	GamepadInput._escape_text_field()
	assert_bool(field.is_editing()).is_false()
	assert_bool(field.has_focus()) \
		.override_failure_message("escape must keep the cursor on the meshed field").is_true()


func test_escape_releases_unmeshed_field() -> void:
	var field := _add_line_edit(false)
	field.grab_focus()
	field.edit()
	GamepadInput._escape_text_field()
	assert_bool(field.has_focus()) \
		.override_failure_message("escape must release an unmeshed field (board chat)").is_false()


func test_confirm_press_starts_editing() -> void:
	var field := _add_line_edit(true)
	field.grab_focus()
	field.unedit()
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	GamepadInput.translate_event(press)
	assert_bool(field.is_editing()) \
		.override_failure_message("A on a focused idle field did not start editing").is_true()


func test_text_area_hint_offers_type() -> void:
	var hints := DeckBuilderPadHints.compute({"area": "text"})
	assert_str(String(hints[0]["text_key"])).is_equal("STR_DB_HINT_TYPE")
	assert_that(hints[0]["action"]).is_equal(&"pad_confirm")
