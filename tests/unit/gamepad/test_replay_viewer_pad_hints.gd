extends GdUnitTestSuite

## ReplayViewerPadHints.compute is pure — assert the hint matrix per context:
## an open overlay wins over the focus area; every state ends in a B hint.


func _actions(hints: Array[Dictionary]) -> Array:
	return hints.map(func(h: Dictionary): return h["action"])


func _keys(hints: Array[Dictionary]) -> Array:
	return hints.map(func(h: Dictionary): return h["text_key"])


func test_zoom_overlay_only_offers_close() -> void:
	var hints := ReplayViewerPadHints.compute({"overlay": "zoom", "area": "card"})
	assert_array(_actions(hints)).is_equal([&"pad_cancel"])
	assert_array(_keys(hints)).is_equal(["STR_GB_HINT_CLOSE"])


func test_gallery_overlay_offers_inspect_and_close() -> void:
	var hints := ReplayViewerPadHints.compute({"overlay": "gallery", "area": "chrome"})
	assert_array(_actions(hints)).is_equal([&"pad_inspect", &"pad_cancel"])
	assert_array(_keys(hints)).is_equal(["STR_GB_HINT_INSPECT", "STR_GB_HINT_CLOSE"])


func test_hand_card_offers_inspect_transport_and_exit() -> void:
	var hints := ReplayViewerPadHints.compute({"overlay": "", "area": "card"})
	assert_array(_keys(hints)).is_equal([
		"STR_GB_HINT_INSPECT", "STR_RV_HINT_STEP", "STR_RV_HINT_TURN", "STR_RV_EXIT"])
	assert_that(hints[0]["action"]).is_equal(&"pad_inspect")


func test_slider_offers_paired_adjust_glyphs() -> void:
	var hints := ReplayViewerPadHints.compute({"area": "slider"})
	assert_array(_keys(hints)).is_equal([
		"STR_RV_HINT_ADJUST", "STR_RV_HINT_STEP", "STR_RV_HINT_TURN", "STR_RV_EXIT"])
	assert_that(hints[0]["action"]).is_equal(&"pad_nav_left")
	assert_that(hints[0]["action2"]).is_equal(&"pad_nav_right")


func test_chrome_default_offers_select_transport_and_exit() -> void:
	var hints := ReplayViewerPadHints.compute({})
	assert_array(_keys(hints)).is_equal([
		"STR_GB_HINT_SELECT", "STR_RV_HINT_STEP", "STR_RV_HINT_TURN", "STR_RV_EXIT"])
	assert_that(hints[0]["action"]).is_equal(&"pad_confirm")
	# Bumpers = single step, triggers = whole turn.
	assert_that(hints[1]["action"]).is_equal(&"pad_focus_log")
	assert_that(hints[1]["action2"]).is_equal(&"pad_focus_tracker")
	assert_that(hints[2]["action"]).is_equal(&"pad_play_card_rage")
	assert_that(hints[2]["action2"]).is_equal(&"pad_play_card_invasion")
	assert_that(hints[3]["action"]).is_equal(&"pad_cancel")
