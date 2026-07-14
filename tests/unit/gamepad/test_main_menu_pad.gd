extends GdUnitTestSuite

## Main-menu pad mesh: the whole screen is deliberately wired into an
## explicit focus graph (not just default spatial nav) — deck pickers, the
## Options/Sound/Music rail, the center stack, and the corner buttons — and
## pressing Patreon/Discord prompts a leave-the-game confirmation instead of
## opening the browser directly.

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
		.is_same(_menu.deck_builder_button)
	assert_object(_neighbor(_menu.extras_button, _menu.extras_button.focus_neighbor_left)) \
		.is_same(_menu.deck_builder_button)
	assert_object(_neighbor(_menu.deck_builder_button, _menu.deck_builder_button.focus_neighbor_bottom)) \
		.is_same(_menu.discord_button)


func test_full_menu_mesh() -> void:
	var p1: Control = _menu.deck_select_p1.pad_focus_targets()[0]
	var p2: Control = _menu.deck_select_p2.pad_focus_targets()[0]
	var start: Control = _menu.start_button
	var bot: Control = _menu.solo_bot_button
	var gear: Control = _menu.bot_config_button
	var lan: Control = _menu.lan_button
	var online: Control = _menu.online_button
	var builder: Control = _menu.deck_builder_button
	var options: Control = _menu.options_button
	var sound: Control = _menu.sound_button
	var music: Control = _menu.music_button
	var discord: Control = _menu.discord_button
	var patreon: Control = _menu.patreon_button
	var extras: Control = _menu.extras_button

	# {node: [left, right, top, bottom]} — self means the edge self-loops.
	var mesh := {
		p1: [p1, p2, p1, start],
		p2: [p1, options, p2, start],
		options: [p2, options, options, sound],
		sound: [p2, sound, options, music],
		music: [p2, music, sound, extras],
		start: [discord, extras, p1, bot],
		bot: [discord, gear, start, lan],
		gear: [bot, gear, start, lan],
		lan: [discord, extras, bot, online],
		online: [discord, extras, lan, builder],
		builder: [discord, extras, online, discord],
		discord: [discord, builder, builder, patreon],
		patreon: [patreon, builder, discord, patreon],
		extras: [builder, extras, music, extras],
	}
	for from: Control in mesh:
		var expected: Array = mesh[from]
		var paths: Array[NodePath] = [
			from.focus_neighbor_left, from.focus_neighbor_right,
			from.focus_neighbor_top, from.focus_neighbor_bottom,
		]
		for i in range(4):
			assert_object(_neighbor(from, paths[i])) \
				.override_failure_message("%s neighbor %d wrong on %s" % [
					["left", "right", "top", "bottom"][i], i, from.name]) \
				.is_same(expected[i])


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
