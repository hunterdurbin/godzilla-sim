extends GdUnitTestSuite

## Controller support for the main menu's Bot Config popup: every control is
## meshed for the dpad, the format dropdown's popup is a registered focus
## context of its own (a focused popup window otherwise swallows joypad
## input entirely), and pad B closes each popup via the TRAILING ui_cancel
## twin — the leading pad_cancel must die inside the window so the second
## twin can't leak into the screen underneath.

const MODAL_META := &"_gamepad_modal"

var _menu: Control


func before_test() -> void:
	_menu = auto_free(load("res://scenes/menus/MainMenu.tscn").instantiate())
	add_child(_menu)


func _open_config_popup() -> PopupPanel:
	_menu._show_bot_config_popup()
	var popup: PopupPanel = null
	for child in _menu.get_children():
		if child is PopupPanel:
			popup = child
	assert_object(popup).override_failure_message("Bot Config popup did not open").is_not_null()
	return popup


func test_popup_and_format_dropdown_are_registered_modals() -> void:
	var popup := _open_config_popup()
	assert_bool(popup.has_meta(MODAL_META)) \
		.override_failure_message("Bot Config popup is not a registered modal").is_true()
	var format_option: OptionButton = popup.find_children("*", "OptionButton", true, false)[0]
	assert_bool(format_option.get_popup().has_meta(MODAL_META)) \
		.override_failure_message("format dropdown popup is not a registered modal").is_true()


func test_every_control_is_meshed() -> void:
	var popup := _open_config_popup()
	for type in ["Button", "OptionButton", "HSlider", "LineEdit", "CheckBox"]:
		for control: Control in popup.find_children("*", type, true, false):
			assert_bool(GamepadHelper.has_focus_neighbors(control)) \
				.override_failure_message("unmeshed %s: %s" % [type, str(control)]).is_true()


func test_pad_back_closes_via_trailing_ui_cancel_twin() -> void:
	var popup := _open_config_popup()
	assert_bool(popup.visible).is_true()
	var lead := InputEventAction.new()
	lead.action = &"pad_cancel"
	lead.pressed = true
	popup.window_input.emit(lead)
	assert_bool(popup.visible) \
		.override_failure_message("leading pad_cancel must not close the popup").is_true()
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	popup.window_input.emit(twin)
	assert_bool(popup.visible) \
		.override_failure_message("trailing ui_cancel twin did not close the popup").is_false()


func test_deck_pool_popup_is_meshed_and_closable() -> void:
	var config := _open_config_popup()
	_menu._show_deck_pool_popup(config,
		{"deck_weights": {}, "folder_weights": {}, "format": ""}, true)
	var inner: PopupPanel = null
	for child in config.get_children():
		if child is PopupPanel:
			inner = child
	assert_object(inner).override_failure_message("deck pool popup did not open").is_not_null()
	assert_bool(inner.has_meta(MODAL_META)) \
		.override_failure_message("deck pool popup is not a registered modal").is_true()
	# The pool's search box is the first LineEdit and must be meshed even
	# with zero deck rows (header band + Save/Cancel band always exist).
	var search: LineEdit = inner.find_children("*", "LineEdit", true, false)[0]
	assert_bool(GamepadHelper.has_focus_neighbors(search)) \
		.override_failure_message("pool search box is not meshed").is_true()
	var twin := InputEventAction.new()
	twin.action = &"ui_cancel"
	twin.pressed = true
	inner.window_input.emit(twin)
	assert_bool(inner.visible) \
		.override_failure_message("B did not close the deck pool popup").is_false()
	assert_bool(config.visible) \
		.override_failure_message("closing the inner popup also closed Bot Config").is_true()
