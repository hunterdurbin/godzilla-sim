extends GdUnitTestSuite

## The Confirm button's glyph must advertise the pad button that actually
## presses it. Only the pass-confirmation jail ("confirm" mode) parks the
## cursor ON the button, where A (pad_confirm) activates it; every other
## prompt consumes A for selection, so the working path is pad_end_main via
## press_primary_button(). _emit_ctx is the single choke point that flips
## the glyph's action per mode.


func _make_controller() -> SelectionController:
	var sel := SelectionController.new()
	sel.confirm_glyph = auto_free(ControllerGlyph.new())
	# Never added to the tree — _emit_ctx only touches the glyph + signal.
	return auto_free(sel)


func test_selection_modes_advertise_end_main() -> void:
	var sel := _make_controller()
	for mode: String in [
			"none", "hand_select", "hand_discard", "card_to_zone",
			"zone_target", "zones_target", "strategy_target", "choice"]:
		sel._emit_ctx(mode)
		assert_str(String(sel.confirm_glyph.action)) \
			.override_failure_message("mode %s must advertise pad_end_main" % mode) \
			.is_equal("pad_end_main")


func test_confirm_mode_advertises_pad_confirm() -> void:
	var sel := _make_controller()
	sel._emit_ctx("confirm")
	assert_str(String(sel.confirm_glyph.action)).is_equal("pad_confirm")
	# Leaving the pass confirmation flips it back.
	sel._emit_ctx("none")
	assert_str(String(sel.confirm_glyph.action)).is_equal("pad_end_main")


func test_missing_glyph_is_tolerated() -> void:
	var sel: SelectionController = auto_free(SelectionController.new())
	sel._emit_ctx("zones_target") # must not crash without a bound glyph
	assert_bool(sel.confirm_glyph == null).is_true()
