extends GdUnitTestSuite

## pop_focus_context restores the control that held focus when the modal's
## context was pushed — the cursor lands back on the button that opened the
## modal. The uncovered context's provider is only the fallback for when
## that control is gone (freed grid wrapper), hidden, or unfocusable.

var _was_gamepad: bool


func before_test() -> void:
	_was_gamepad = GamepadHelper._using_gamepad
	GamepadHelper._using_gamepad = true


func after_test() -> void:
	GamepadHelper._using_gamepad = _was_gamepad
	GamepadHelper._return_focus = null


func _add_button() -> Button:
	var button := Button.new()
	add_child(button)
	return button


func test_pop_restores_the_control_focused_at_push() -> void:
	var base_target := auto_free(_add_button()) as Button
	var opener := auto_free(_add_button()) as Button
	var modal_button := auto_free(_add_button()) as Button
	var base_owner := auto_free(Node.new()) as Node
	add_child(base_owner)
	var modal_owner := auto_free(Node.new()) as Node
	add_child(modal_owner)

	GamepadHelper.push_focus_context(base_owner, func() -> Control: return base_target)
	await await_idle_frame()
	opener.grab_focus()  # the cursor walked away from the provider's default

	GamepadHelper.push_focus_context(modal_owner, func() -> Control: return modal_button)
	await await_idle_frame()
	assert_bool(modal_button.has_focus()) \
		.override_failure_message("push did not focus the modal's provider target").is_true()

	GamepadHelper.pop_focus_context(modal_owner)
	await await_idle_frame()
	assert_bool(opener.has_focus()) \
		.override_failure_message("pop did not restore the control focused at push").is_true()

	GamepadHelper.pop_focus_context(base_owner)
	await await_idle_frame()


func test_pop_falls_back_to_provider_when_remembered_control_is_gone() -> void:
	var base_target := auto_free(_add_button()) as Button
	var opener := _add_button()  # freed mid-test — no auto_free
	var modal_button := auto_free(_add_button()) as Button
	var base_owner := auto_free(Node.new()) as Node
	add_child(base_owner)
	var modal_owner := auto_free(Node.new()) as Node
	add_child(modal_owner)

	GamepadHelper.push_focus_context(base_owner, func() -> Control: return base_target)
	await await_idle_frame()
	opener.grab_focus()
	GamepadHelper.push_focus_context(modal_owner, func() -> Control: return modal_button)
	await await_idle_frame()

	opener.free()  # e.g. a grid rebuild replaced the wrapper while the modal was up
	GamepadHelper.pop_focus_context(modal_owner)
	await await_idle_frame()
	assert_bool(base_target.has_focus()) \
		.override_failure_message("pop did not fall back to the provider").is_true()

	GamepadHelper.pop_focus_context(base_owner)
	await await_idle_frame()
