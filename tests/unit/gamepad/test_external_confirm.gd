extends GdUnitTestSuite

## ExternalConfirm gates every leave-the-game action (browser URL, OS file
## manager) behind a ConfirmationDialog: nothing opens until OK, the dialog is
## a registered gamepad modal, pad B closes it on the LEADING pad_cancel with
## the mirrored ui_cancel twin swallowed, and the dialog frees itself on hide.

const MODAL_META := &"_gamepad_modal"
const FAKE_URL := "https://discord.gg/fwCaYzWbPw"

var _host: Control
var _opened: Array = []


func before_test() -> void:
	GamepadHelper._cancel_swallow_frame = -100  # no stale twin swallow
	var opened: Array = []
	_opened = opened
	ExternalConfirm._shell_open = func(target: String) -> void: opened.append(target)
	_host = auto_free(Control.new())
	add_child(_host)


func after_test() -> void:
	ExternalConfirm._shell_open = Callable(OS, "shell_open")


func _last_dialog() -> ConfirmationDialog:
	var dialog: ConfirmationDialog = null
	for child in _host.get_children():
		if child is ConfirmationDialog:
			dialog = child
	assert_object(dialog).override_failure_message("no confirm dialog opened").is_not_null()
	return dialog


func _press_pad_cancel(dialog: ConfirmationDialog) -> void:
	# The LEADING pad_cancel closes; emit the mirrored ui_cancel twin too and
	# rely on the swallow stamp to make it a no-op (a real press sends both).
	var lead := InputEventAction.new()
	lead.action = &"pad_cancel"
	lead.pressed = true
	dialog.window_input.emit(lead)
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	dialog.window_input.emit(twin)


func test_open_url_prompts_instead_of_opening() -> void:
	ExternalConfirm.open_url(_host, FAKE_URL)
	var dialog := _last_dialog()
	assert_bool(dialog.visible).is_true()
	assert_bool(dialog.has_meta(MODAL_META)) \
		.override_failure_message("confirm dialog is not a registered modal").is_true()
	assert_array(_opened) \
		.override_failure_message("URL opened without confirmation").is_empty()
	# The prompt names only the destination host — never the full URL (the
	# bug-report URL carries a huge uri-encoded body).
	assert_str(dialog.dialog_text).contains("discord.gg")
	assert_bool(dialog.dialog_text.contains("https")).is_false()


func test_confirmed_opens_target_once() -> void:
	ExternalConfirm.open_url(_host, FAKE_URL)
	var dialog := _last_dialog()
	dialog.confirmed.emit()
	assert_array(_opened).contains_exactly([FAKE_URL])
	# Every close path hides first; hiding frees the one-shot dialog.
	dialog.hide()
	assert_bool(dialog.is_queued_for_deletion()) \
		.override_failure_message("dialog must free itself on hide").is_true()


func test_pad_cancel_closes_without_opening() -> void:
	ExternalConfirm.open_url(_host, FAKE_URL)
	var dialog := _last_dialog()
	_press_pad_cancel(dialog)
	assert_bool(dialog.visible) \
		.override_failure_message("leading pad_cancel did not close the dialog").is_false()
	assert_array(_opened) \
		.override_failure_message("pad B must never open the destination").is_empty()
	assert_bool(dialog.is_queued_for_deletion()).is_true()


func test_open_folder_prompt_shows_path() -> void:
	var path := "user://exports/logs"
	ExternalConfirm.open_folder(_host, path)
	var dialog := _last_dialog()
	assert_str(dialog.dialog_text).contains(path)
	assert_array(_opened).is_empty()
	dialog.confirmed.emit()
	assert_array(_opened).contains_exactly([path])
