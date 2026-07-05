extends GdUnitTestSuite

## Opens the Options → Controller rebind modal through the same handler the
## button click runs (regression: _on_controller_pressed crashed on an
## undefined GamepadInput member that only resolved at click time).

var _options: Control


func before_test() -> void:
	_options = auto_free(load("res://scenes/menus/Options.tscn").instantiate())
	add_child(_options)


func test_controller_modal_opens_with_a_row_per_rebindable_action() -> void:
	_options._on_controller_pressed()
	await await_idle_frame()

	var popup: PopupPanel = null
	for child in _options.get_children():
		if child is PopupPanel:
			popup = child
	assert_object(popup).override_failure_message("Controller modal did not open").is_not_null()

	var glyphs := popup.find_children("*", "ControllerGlyph", true, false)
	var expected: Array[StringName] = GamepadInput.get_rebindable_actions()
	assert_int(glyphs.size()) \
		.override_failure_message("Expected one glyph per rebindable action") \
		.is_equal(expected.size())
	for i in range(glyphs.size()):
		assert_that((glyphs[i] as ControllerGlyph).action).is_equal(expected[i])


func test_rebindable_actions_match_default_map() -> void:
	var actions := GamepadInput.get_rebindable_actions()
	var defaults := GlyphDB.default_map()
	assert_int(actions.size()).is_equal(defaults.size())
	for logical in actions:
		assert_bool(defaults.has(logical)).is_true()
