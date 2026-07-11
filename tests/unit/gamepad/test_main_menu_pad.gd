extends GdUnitTestSuite

## Main-menu social buttons on the pad: Patreon/Discord are deliberately
## wired into the focus mesh (not just default spatial nav), and pressing
## either one prompts a leave-the-game confirmation instead of opening the
## browser directly.

const MODAL_META := &"_gamepad_modal"

var _menu: Control
var _opened: Array = []


func before_test() -> void:
	GamepadHelper._cancel_swallow_frame = -100  # no stale twin swallow
	var opened: Array = []
	_opened = opened
	ExternalConfirm._shell_open = func(target: String) -> void: opened.append(target)
	_menu = auto_free(load("res://scenes/menus/MainMenu.tscn").instantiate())
	add_child(_menu)


func after_test() -> void:
	ExternalConfirm._shell_open = Callable(OS, "shell_open")


func _neighbor(from: Control, path: NodePath) -> Control:
	assert_bool(path.is_empty()) \
		.override_failure_message("no focus neighbor wired on %s" % from.name).is_false()
	return from.get_node(path) as Control


func test_social_buttons_are_meshed() -> void:
	for button: Control in [_menu.patreon_button, _menu.discord_button]:
		assert_bool(GamepadHelper.has_focus_neighbors(button)) \
			.override_failure_message("unmeshed social button: %s" % button.name).is_true()
	assert_object(_neighbor(_menu.discord_button, _menu.discord_button.focus_neighbor_bottom)) \
		.is_same(_menu.patreon_button)
	assert_object(_neighbor(_menu.patreon_button, _menu.patreon_button.focus_neighbor_top)) \
		.is_same(_menu.discord_button)
	assert_object(_neighbor(_menu.patreon_button, _menu.patreon_button.focus_neighbor_right)) \
		.is_same(_menu.extras_button)
	assert_object(_neighbor(_menu.deck_builder_button, _menu.deck_builder_button.focus_neighbor_bottom)) \
		.is_same(_menu.discord_button)


func _last_confirm_dialog() -> ConfirmationDialog:
	var dialog: ConfirmationDialog = null
	for child in _menu.get_children():
		if child is ConfirmationDialog:
			dialog = child
	assert_object(dialog).override_failure_message("no confirm dialog opened").is_not_null()
	return dialog


func test_patreon_press_prompts_instead_of_opening() -> void:
	_menu._on_patreon_pressed()
	var dialog := _last_confirm_dialog()
	assert_bool(dialog.has_meta(MODAL_META)) \
		.override_failure_message("leave-game confirm is not a registered modal").is_true()
	assert_str(dialog.dialog_text).contains("patreon.com")
	assert_array(_opened) \
		.override_failure_message("Patreon opened without confirmation").is_empty()
	dialog.confirmed.emit()
	assert_array(_opened).contains_exactly([_menu.PATREON_URL])


func test_discord_press_prompts_instead_of_opening() -> void:
	_menu._on_discord_pressed()
	var dialog := _last_confirm_dialog()
	assert_str(dialog.dialog_text).contains("discord.gg")
	assert_array(_opened).is_empty()
