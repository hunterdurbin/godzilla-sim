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


# --- Rebindable-action edge tracking -----------------------------------------
# The triggers are bound to analog axes (project.godot axes 4/5): a held
# trigger restreams InputEventJoypadMotion (Steam Input: every frame) and each
# event past the deadzone reports is_action_pressed() == true. Without edge
# tracking, GamepadInput injected pad_play_card_rage once per event — on Steam
# Deck one rage discard per frame until the hand was empty.


## Records _inject calls instead of touching the real Input singleton.
class RecordingPad extends "res://scripts/input/gamepad_input.gd":
	var injections: Array = []

	func _inject(logical: StringName, pressed: bool) -> void:
		injections.append([logical, pressed])


func _recording_pad() -> RecordingPad:
	var pad: RecordingPad = auto_free(RecordingPad.new())
	add_child(pad)
	return pad


func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.pressed = pressed
	return ev


func test_held_trigger_stream_injects_single_press() -> void:
	var pad := _recording_pad()
	for i in 5:
		pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_that(pad.injections).is_equal([[&"pad_play_card_rage", true]])
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true], [&"pad_play_card_rage", false]])


func test_trigger_wobble_above_deadzone_injects_single_press() -> void:
	var pad := _recording_pad()
	for value in [1.0, 0.9, 1.0]:
		pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, value))
	assert_that(pad.injections).is_equal([[&"pad_play_card_rage", true]])


func test_deadzone_crossings_are_genuine_edges() -> void:
	var pad := _recording_pad()
	for value in [1.0, 0.0, 1.0]:
		pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, value))
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true],
		[&"pad_play_card_rage", false],
		[&"pad_play_card_rage", true]])


func test_below_deadzone_stream_injects_nothing() -> void:
	var pad := _recording_pad()
	for i in 3:
		pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 0.15))
	assert_that(pad.injections).is_equal([])


func test_both_triggers_track_independently() -> void:
	var pad := _recording_pad()
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true],
		[&"pad_play_card_invasion", true],
		[&"pad_play_card_rage", false]])
	assert_that(pad._action_held).is_equal(
		{&"controller_trigger_r": &"pad_play_card_invasion"})


func test_duplicate_button_presses_dedupe() -> void:
	var pad := _recording_pad()
	pad.translate_event(_button(JOY_BUTTON_A, true))
	pad.translate_event(_button(JOY_BUTTON_A, true))
	assert_that(pad.injections).is_equal([[&"pad_confirm", true]])
	pad.translate_event(_button(JOY_BUTTON_A, false))
	assert_that(pad.injections).is_equal([
		[&"pad_confirm", true], [&"pad_confirm", false]])


func test_disconnect_flushes_held_actions() -> void:
	var pad := _recording_pad()
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	pad._on_joy_connection_changed(0, false)
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true], [&"pad_play_card_rage", false]])
	assert_that(pad._action_held).is_equal({})


func test_rebind_mid_hold_releases_old_logical() -> void:
	var pad := _recording_pad()
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	pad.rebind(&"pad_play_card_rage", &"controller_stick_press_l")
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true], [&"pad_play_card_rage", false]])
	# Nothing maps to the left trigger any more: further axis events no-op.
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_that(pad.injections.size()).is_equal(2)


func test_focus_out_flushes_held_actions() -> void:
	var pad := _recording_pad()
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	pad.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true], [&"pad_play_card_rage", false]])
	assert_that(pad._action_held).is_equal({})


func test_release_survives_capture_guard() -> void:
	var pad := _recording_pad()
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	pad.begin_capture(func(_physical: StringName) -> void: pass)
	pad.translate_event(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	pad.cancel_capture()
	assert_that(pad.injections).is_equal([
		[&"pad_play_card_rage", true], [&"pad_play_card_rage", false]])
