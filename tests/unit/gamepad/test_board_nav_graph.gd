extends GdUnitTestSuite

## BoardNavGraph — the unified controller-navigation graph builder: static
## table closure, dynamic hand/tracker/choice rows, the "hand"/"tracker"
## sentinel expansion (nearest-by-X hand entry, full tracker column), and the
## zone-jail edge override (wrap-around z1-z8 rows during zone prompts).

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


func _build(hand_count: int, mobile: bool = false, tracker_count: int = 0, choice_count: int = 0, stack_count: int = 0, zone_jail_side: String = "") -> Dictionary:
	return BoardNavGraph.build({
		"mobile": mobile,
		"hand_count": hand_count,
		"tracker_count": tracker_count,
		"choice_count": choice_count,
		"stack_count": stack_count,
		"zone_jail_side": zone_jail_side,
		"rect_of": _rects(hand_count),
	})


func test_desktop_build_is_closed() -> void:
	# Every id referenced by any direction must be a mapped element itself —
	# typos in the hand-edited tables become test failures, not dead ends.
	var map := _build(5, false, 3, 2, 2)
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


func test_empty_hand_sort_buttons_can_return_to_board() -> void:
	# With no hand cards, every bottom-row zone descends into the sort button
	# (the empty-hand stand-in), so the sort/toggle pocket must carry the hand
	# row's return exits back up to the board — otherwise the cursor is trapped.
	var map := _build(0)
	assert_that(map["bot_z2"]["down"]).is_equal(["ap_sort_hand"])
	for board_exit: String in BoardNavGraph.HAND_EXITS:
		assert_array(map["ap_sort_hand"]["up"]).contains([board_exit])
		assert_array(map["ap_hand_toggle"]["up"]).contains([board_exit])


func test_populated_hand_sort_button_up_is_unchanged() -> void:
	# The escape edges only appear with an empty hand; the vertical column stands.
	var map := _build(3)
	assert_that(map["ap_sort_hand"]["up"]).is_equal(["ap_hand_toggle"])


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


func test_stack_column_chains_and_seams_into_choice() -> void:
	var map := _build(2, false, 0, 2, 3)
	assert_that(map["stack_0"]["up"]).is_equal([])
	assert_that(map["stack_0"]["down"]).is_equal(["stack_1"])
	assert_that(map["stack_2"]["up"]).is_equal(["stack_1"])
	# Bottom stack row chains into the choice column, and choice_0 back up.
	assert_that(map["stack_2"]["down"]).is_equal(["choice_0"])
	assert_that(map["choice_0"]["up"]).is_equal(["stack_2"])
	# Free-browse exit: left walks onto the top board's right edge.
	assert_that(map["stack_1"]["left"]).is_equal(["top_monster_deck", "top_z1"])


func test_stack_column_without_choice_dead_ends_down() -> void:
	var map := _build(2, false, 0, 0, 2)
	assert_that(map["stack_1"]["down"]).is_equal([])
	assert_bool(map.has("choice_0")).is_false()


func test_no_stack_rows_leaves_right_edge_untouched() -> void:
	# No board element points AT the stack: with zero rows the map has no
	# stack ids and the choice column keeps its plain top edge.
	var map := _build(2, false, 0, 2, 0)
	assert_bool(map.has("stack_0")).is_false()
	assert_that(map["choice_0"]["up"]).is_equal([])
	for id: String in map:
		for dir: String in DIRS:
			assert_that(map[id].get(dir, [])).not_contains(["stack_0"])


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


func test_desktop_save_button_is_stitched_above_log_panel() -> void:
	var map := _build(3, false, 2)
	assert_that(map["sys_save"]["right"]).is_equal(["top_discard"])
	assert_that(map["sys_save"]["down"]).is_equal(["log_panel"])
	assert_that(map["log_panel"]["up"]).is_equal(["sys_save"])
	# Live entries: on the log itself the dpad scrolls, so top_discard is
	# the route the cursor actually walks.
	assert_that(map["top_discard"]["up"]).is_equal(["sys_save"])
	assert_that(map["top_discard"]["left"]).contains(["sys_save"])


func test_mobile_build_has_no_save_button_node() -> void:
	var map := _build(3, true)
	assert_bool(map.has("sys_save")).is_false()
	assert_that(map["top_discard"]["left"]).not_contains(["sys_save"])


func test_no_zone_jail_keeps_free_browse_zone_edges() -> void:
	var map := _build(3)
	assert_that(map["bot_z1"]["up"]).is_equal(["bot_rage"])
	assert_that(map["bot_z1"]["left"]).is_equal(["bot_monster_deck"])
	assert_that(map["bot_z6"]["right"]).is_equal(["bot_deck"])
	assert_that(map["bot_z5"]["down"][0]).is_equal("hand_2")


func test_zone_jail_bot_rows_wrap_horizontally() -> void:
	var map := _build(3, false, 0, 0, 0, "bot")
	# Lower row z1..z5 chains and wraps at the ends.
	assert_that(map["bot_z1"]["right"]).is_equal(["bot_z2"])
	assert_that(map["bot_z1"]["left"]).is_equal(["bot_z5"])
	assert_that(map["bot_z5"]["right"]).is_equal(["bot_z1"])
	# Upper row z8|z7|z6 chains and wraps at the ends.
	assert_that(map["bot_z8"]["left"]).is_equal(["bot_z6"])
	assert_that(map["bot_z6"]["right"]).is_equal(["bot_z8"])
	assert_that(map["bot_z8"]["right"]).is_equal(["bot_z7"])


func test_zone_jail_bot_verticals_pair_and_wrap() -> void:
	var map := _build(3, false, 0, 0, 0, "bot")
	# Up AND down both reach the paired zone in the other row.
	assert_that(map["bot_z3"]["up"]).is_equal(["bot_z8"])
	assert_that(map["bot_z3"]["down"]).is_equal(["bot_z8"])
	assert_that(map["bot_z8"]["up"]).is_equal(["bot_z3"])
	assert_that(map["bot_z8"]["down"]).is_equal(["bot_z3"])
	assert_that(map["bot_z4"]["up"]).is_equal(["bot_z7"])
	assert_that(map["bot_z7"]["down"]).is_equal(["bot_z4"])
	assert_that(map["bot_z6"]["up"]).is_equal(["bot_z5"])
	assert_that(map["bot_z5"]["down"]).is_equal(["bot_z6"])
	# z1/z2 route to z8 one-way — z8 only ever returns to z3.
	assert_that(map["bot_z1"]["up"]).is_equal(["bot_z8"])
	assert_that(map["bot_z1"]["down"]).is_equal(["bot_z8"])
	assert_that(map["bot_z2"]["up"]).is_equal(["bot_z8"])


func test_zone_jail_cuts_free_browse_exits() -> void:
	var map := _build(3, false, 2, 0, 0, "bot")
	# The jailed side's zones no longer reach rage/hand/deck/discard...
	for zone_num in range(1, 9):
		var entry: Dictionary = map["bot_z%d" % zone_num]
		for dir: String in DIRS:
			for target: String in entry.get(dir, []):
				assert_bool(target.begins_with("bot_z")) \
					.override_failure_message("bot_z%d.%s escapes jail to '%s'" % [zone_num, dir, target]) \
					.is_true()
	# ...while the other side keeps its free-browse rows untouched.
	assert_that(map["top_z3"]["down"]).is_equal(["top_z8"])
	assert_that(map["top_z1"]["right"]).is_equal(["top_monster_deck"])


func test_zone_jail_top_side_flips_both_axes() -> void:
	var map := _build(3, false, 0, 0, 0, "top")
	# The top playmat is mirrored on both axes: left/right and up/down swap.
	assert_that(map["top_z1"]["left"]).is_equal(["top_z2"])
	assert_that(map["top_z1"]["right"]).is_equal(["top_z5"])
	assert_that(map["top_z5"]["left"]).is_equal(["top_z1"])
	assert_that(map["top_z6"]["left"]).is_equal(["top_z8"])
	assert_that(map["top_z8"]["right"]).is_equal(["top_z6"])
	# Verticals flip too (up/down symmetric in the jail table, so both point
	# at the paired zone either way).
	assert_that(map["top_z1"]["down"]).is_equal(["top_z8"])
	assert_that(map["top_z1"]["up"]).is_equal(["top_z8"])
	assert_that(map["top_z8"]["down"]).is_equal(["top_z3"])
	assert_that(map["top_z8"]["up"]).is_equal(["top_z3"])
	# Bottom board keeps free-browse edges.
	assert_that(map["bot_z1"]["up"]).is_equal(["bot_rage"])


func test_zone_jail_build_stays_closed() -> void:
	for side in ["bot", "top"]:
		var map := _build(5, false, 3, 2, 2, side)
		for id: String in map:
			for dir: String in DIRS:
				for target: String in map[id].get(dir, []):
					assert_bool(map.has(target)) \
						.override_failure_message("[%s jail] %s.%s -> unmapped '%s'" % [side, id, dir, target]) \
						.is_true()


func test_set_map_preserves_history() -> void:
	var map := CursorMap.new(_build(3))
	map.push_visited("bot_z2")
	map.push_visited("hand_1")
	map.set_map(_build(2))
	# "up from the hand returns where you came from" must survive a rebuild.
	assert_that(map.visited()).is_equal(["bot_z2", "hand_1"] as Array[String])
	assert_str(map.next("hand_0", "up")).is_equal("bot_z2")
