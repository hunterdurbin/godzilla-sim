extends GdUnitTestSuite

## BoardNavGraph — the unified controller-navigation graph builder: static
## table closure, dynamic hand/tracker/choice rows, and the "hand"/"tracker"
## sentinel expansion (nearest-by-X hand entry, full tracker column).

const DIRS := ["up", "right", "down", "left"]


func _rects(hand_count: int) -> Callable:
	# Fake geometry: board elements sit on a coarse grid, hand cards fan
	# left-to-right at the bottom (80px apart, matching nothing in
	# particular — only relative X order matters).
	var element_x := {
		"bot_monster_deck": 100.0, "bot_z1": 250.0, "bot_z2": 400.0,
		"bot_z3": 550.0, "bot_z4": 700.0, "bot_z5": 850.0,
		"bot_discard": 1000.0, "ap_hand_toggle": 1100.0,
		"ap_sort_hand": 1180.0, "ap_cancel": 900.0,
	}
	return func(id: String) -> Rect2:
		if id.begins_with("hand_"):
			var i := id.substr(5).to_int()
			if i >= hand_count:
				return Rect2()
			return Rect2(Vector2(300.0 + i * 80.0, 600.0), Vector2(70.0, 100.0))
		if element_x.has(id):
			return Rect2(Vector2(element_x[id], 400.0), Vector2(120.0, 120.0))
		return Rect2(Vector2(500.0, 300.0), Vector2(100.0, 100.0))


func _build(hand_count: int, mobile: bool = false, tracker_count: int = 0, choice_count: int = 0) -> Dictionary:
	return BoardNavGraph.build({
		"mobile": mobile,
		"hand_count": hand_count,
		"tracker_count": tracker_count,
		"choice_count": choice_count,
		"rect_of": _rects(hand_count),
	})


func test_desktop_build_is_closed() -> void:
	# Every id referenced by any direction must be a mapped element itself —
	# typos in the hand-edited tables become test failures, not dead ends.
	var map := _build(5, false, 3, 0)
	for id: String in map:
		for dir: String in DIRS:
			for target: String in map[id].get(dir, []):
				assert_bool(map.has(target)) \
					.override_failure_message("%s.%s -> unmapped '%s'" % [id, dir, target]) \
					.is_true()


func test_sentinels_are_fully_expanded() -> void:
	for mobile in [false, true]:
		var map := _build(3, mobile, 2, 2)
		for id: String in map:
			for dir: String in DIRS:
				var targets: Array = map[id].get(dir, [])
				assert_bool(BoardNavGraph.HAND_SENTINEL in targets or BoardNavGraph.TRACKER_SENTINEL in targets) \
					.override_failure_message("unexpanded sentinel in %s.%s" % [id, dir]) \
					.is_false()


func test_hand_row_chains_left_to_right() -> void:
	var map := _build(3)
	assert_that(map["hand_0"]["left"]).is_equal([])
	assert_that(map["hand_0"]["right"]).is_equal(["hand_1"])
	assert_that(map["hand_1"]["left"]).is_equal(["hand_0"])
	assert_that(map["hand_2"]["right"]).is_equal(["ap_sort_hand"])
	assert_that(map["hand_1"]["up"]).is_equal(BoardNavGraph.HAND_EXITS)


func test_desktop_hand_buttons_are_stacked_vertically() -> void:
	# Desktop reparents toggle/sort into a vertical column (toggle above sort);
	# the graph must link them up/down, not left/right.
	var map := _build(3)
	assert_that(map["ap_hand_toggle"]["down"]).is_equal(["ap_sort_hand"])
	assert_that(map["ap_sort_hand"]["up"]).is_equal(["ap_hand_toggle"])
	assert_that(map["ap_hand_toggle"]["right"]).not_contains(["ap_sort_hand"])
	assert_that(map["ap_sort_hand"]["left"]).not_contains(["ap_hand_toggle"])


func test_mobile_hand_buttons_stay_side_by_side() -> void:
	# Mobile keeps the pair in an HBox split pill — horizontal wiring stands.
	var map := _build(3, true)
	assert_that(map["ap_hand_toggle"]["right"]).is_equal(["ap_sort_hand"])
	assert_that(map["ap_sort_hand"]["left"]).is_equal(["ap_hand_toggle"])


func test_hand_entry_picks_nearest_card_by_x() -> void:
	var map := _build(5)
	# bot_z1 (x≈250) is nearest hand_0 (x≈300); bot_z5 (x≈850) nearest the
	# right end of the fan; the hand stack enters at the rightmost card.
	assert_that(map["bot_z1"]["down"][0]).is_equal("hand_0")
	assert_that(map["bot_z5"]["down"][0]).is_equal("hand_4")
	assert_that(map["ap_hand_toggle"]["left"][0]).is_equal("hand_4")


func test_empty_hand_redirects_to_sort_button() -> void:
	var map := _build(0)
	assert_that(map["bot_z2"]["down"]).contains(["ap_sort_hand"])
	assert_bool(map.has("hand_0")).is_false()
	# The sort button itself must not gain a self-edge.
	assert_that(map["ap_sort_hand"].get("left", [])).not_contains(["ap_sort_hand"])


func test_tracker_column_chains_and_stitches_on_desktop() -> void:
	var map := _build(2, false, 3)
	assert_that(map["trk_0"]["up"]).is_equal(["sys_export_log"])
	assert_that(map["trk_0"]["down"]).is_equal(["trk_1"])
	assert_that(map["trk_2"]["down"]).is_equal(["ap_cancel", "ap_confirm"])
	assert_that(map["trk_1"]["left"]).contains(["bot_deck"])
	# The board's right edge expands "tracker" to every label.
	assert_that(map["bot_deck"]["right"]).contains(["trk_0", "trk_1", "trk_2"])


func test_mobile_tracker_is_bumper_only() -> void:
	var map := _build(2, true, 3)
	# The tracker chain exists but is NOT stitched into the spatial graph —
	# no board element references trk ids; only the bumper reaches them.
	assert_that(map["trk_0"]["up"]).is_equal([])
	assert_that(map["trk_2"]["down"]).is_equal([])
	assert_that(map["trk_1"]["left"]).is_equal([])
	for id: String in map:
		if id.begins_with("trk_") or id.begins_with("hand_"):
			continue
		for dir: String in DIRS:
			assert_that(map[id].get(dir, [])).not_contains(["trk_0"])


func test_no_tracker_labels_drops_sentinel() -> void:
	var map := _build(2, false, 0)
	assert_that(map["bot_deck"]["right"]).is_equal([])
	assert_bool(map.has("trk_0")).is_false()


func test_choice_column_chains_vertically() -> void:
	var map := _build(2, false, 0, 3)
	assert_that(map["choice_0"]["up"]).is_equal([])
	assert_that(map["choice_0"]["down"]).is_equal(["choice_1"])
	assert_that(map["choice_2"]["up"]).is_equal(["choice_1"])
	assert_that(map["choice_2"]["down"]).is_equal([])


func test_mobile_fab_grid_edges() -> void:
	var map := _build(1, true)
	assert_that(map["ap_play_battle"]["right"]).is_equal(["ap_play_monster"])
	assert_that(map["ap_gain_rage"]["down"]).is_equal(["ap_fab_main"])
	assert_that(map["ap_fab_main"]["left"]).is_equal(["ap_end_main"])
	assert_that(map["hand_0"]["right"]).is_equal(["ap_sort_hand", "ap_cancel"])


func test_desktop_log_panel_is_stitched_both_ways() -> void:
	var map := _build(1)
	assert_that(map["log_panel"]["right"]).contains(["top_deck", "bot_strategy_0"])
	assert_that(map["bot_strategy_0"]["left"]).contains(["log_panel"])
	assert_that(map["top_discard"]["left"]).contains(["log_panel"])


func test_set_map_preserves_history() -> void:
	var map := CursorMap.new(_build(3))
	map.push_visited("bot_z2")
	map.push_visited("hand_1")
	map.set_map(_build(2))
	# "up from the hand returns where you came from" must survive a rebuild.
	assert_that(map.visited()).is_equal(["bot_z2", "hand_1"] as Array[String])
	assert_str(map.next("hand_0", "up")).is_equal("bot_z2")
