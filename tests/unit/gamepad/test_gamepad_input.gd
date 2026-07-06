extends GdUnitTestSuite

## GamepadInput rebinding — swap-on-conflict, persistence round-trip through
## GameSettings, reset, and the ui_* mirror table. Uses a fresh instance of
## the autoload script so the real GamepadInput singleton stays untouched.

var _pad: Node
var _saved_bindings: Dictionary
var _saved_type: String


func before_test() -> void:
	_saved_bindings = GameSettings.controller_bindings
	_saved_type = GameSettings.controller_mapping_type
	GameSettings.controller_bindings = {}
	GameSettings.controller_mapping_type = ""
	_pad = auto_free(load("res://scripts/input/gamepad_input.gd").new())
	add_child(_pad)


func after_test() -> void:
	GameSettings.controller_bindings = _saved_bindings
	GameSettings.controller_mapping_type = _saved_type
	GameSettings.save()


func test_defaults_loaded_on_ready() -> void:
	assert_that(_pad.get_physical(&"pad_confirm")).is_equal(&"controller_face_south")
	assert_that(_pad.get_physical(&"pad_cancel")).is_equal(&"controller_face_east")


func test_nav_actions_report_dpad_physical() -> void:
	assert_that(_pad.get_physical(&"pad_nav_up")).is_equal(&"controller_dpad_up")
	assert_that(_pad.get_physical(&"pad_nav_right")).is_equal(&"controller_dpad_right")


func test_rebind_simple() -> void:
	_pad.rebind(&"pad_inspect", &"controller_stick_press_l")
	assert_that(_pad.get_physical(&"pad_inspect")).is_equal(&"controller_stick_press_l")


func test_rebind_swaps_on_conflict() -> void:
	# pad_confirm takes pad_cancel's button; pad_cancel must inherit
	# pad_confirm's old button, never share.
	_pad.rebind(&"pad_confirm", &"controller_face_east")
	assert_that(_pad.get_physical(&"pad_confirm")).is_equal(&"controller_face_east")
	assert_that(_pad.get_physical(&"pad_cancel")).is_equal(&"controller_face_south")


func test_rebind_rejects_unknown_targets() -> void:
	_pad.rebind(&"pad_confirm", &"controller_lstick_up")
	assert_that(_pad.get_physical(&"pad_confirm")).is_equal(&"controller_face_south")
	_pad.rebind(&"pad_bogus", &"controller_face_north")
	assert_that(_pad.get_physical(&"pad_bogus")).is_equal(&"")


func test_rebind_persists_only_diffs_from_defaults() -> void:
	_pad.rebind(&"pad_inspect", &"controller_stick_press_l")
	assert_that(GameSettings.controller_bindings).is_equal({
		"pad_inspect": "controller_stick_press_l",
	})
	assert_str(GameSettings.controller_mapping_type).is_equal(_pad.controller_type)


func test_saved_bindings_apply_for_matching_controller_type() -> void:
	GameSettings.controller_bindings = {"pad_inspect": "controller_stick_press_l"}
	GameSettings.controller_mapping_type = _pad.controller_type
	_pad._load_bindings()
	assert_that(_pad.get_physical(&"pad_inspect")).is_equal(&"controller_stick_press_l")


func test_saved_bindings_discarded_for_other_controller_type() -> void:
	GameSettings.controller_bindings = {"pad_inspect": "controller_stick_press_l"}
	GameSettings.controller_mapping_type = "some_other_type"
	_pad._load_bindings()
	assert_that(_pad.get_physical(&"pad_inspect")).is_equal(&"controller_face_north")


func test_reset_to_defaults() -> void:
	_pad.rebind(&"pad_confirm", &"controller_face_north")
	_pad.reset_to_defaults()
	assert_that(_pad.get_physical(&"pad_confirm")).is_equal(&"controller_face_south")
	assert_that(GameSettings.controller_bindings).is_equal({})


func test_rebind_emits_input_rebound() -> void:
	var monitor := monitor_signals(_pad)
	_pad.rebind(&"pad_end_main", &"controller_bumper_l")
	await assert_signal(monitor).is_emitted("input_rebound")


func test_glyph_style_override() -> void:
	var saved: String = GameSettings.controller_glyph_style
	GameSettings.controller_glyph_style = "playstation"
	assert_str(_pad.glyph_type()).is_equal("playstation")
	GameSettings.controller_glyph_style = "auto"
	assert_str(_pad.glyph_type()).is_equal(_pad.controller_type)
	GameSettings.controller_glyph_style = "bogus"
	assert_str(_pad.glyph_type()).is_equal(_pad.controller_type)
	GameSettings.controller_glyph_style = saved


func test_ui_mirror_covers_nav_and_confirm_cancel() -> void:
	var mirror: Dictionary = _pad.UI_MIRROR
	assert_that(mirror[&"pad_confirm"]).is_equal(&"ui_accept")
	assert_that(mirror[&"pad_cancel"]).is_equal(&"ui_cancel")
	for direction in ["up", "down", "left", "right"]:
		assert_that(mirror[StringName("pad_nav_" + direction)]) \
			.is_equal(StringName("ui_" + direction))
