extends GdUnitTestSuite

## BotConfig difficulty presets — KAIJU tier plumbing. The planner must be
## opt-in per preset: only kaiju() enables it, and adding the tier must not
## disturb the existing EASY/NORMAL/HARD knobs (seed-matched sim diffs rely
## on those presets staying byte-identical).


func test_from_difficulty_kaiju_returns_planner_preset() -> void:
	var c := BotConfig.from_difficulty(BotConfig.Difficulty.KAIJU)
	assert_bool(c.use_planner).is_true()
	assert_float(c.action_delay).is_equal(0.2)


func test_kaiju_inherits_hard_scoring() -> void:
	var k := BotConfig.kaiju()
	var h := BotConfig.hard()
	assert_int(k.tag_scores["destroys_zone"]).is_equal(h.tag_scores["destroys_zone"])
	assert_that(k.enabled_combos).is_equal(h.enabled_combos)
	assert_int(k.early_invasion_zone_threshold).is_equal(h.early_invasion_zone_threshold)


func test_other_presets_do_not_enable_planner() -> void:
	assert_bool(BotConfig.easy().use_planner).is_false()
	assert_bool(BotConfig.normal().use_planner).is_false()
	assert_bool(BotConfig.hard().use_planner).is_false()


func test_normal_preset_defaults_unchanged() -> void:
	var c := BotConfig.normal()
	assert_float(c.action_delay).is_equal(0.5)
	assert_int(c.base_play_score).is_equal(10)
	assert_int(c.tag_scores["destroys_zone"]).is_equal(30)
	assert_int(c.choice_pick_mode).is_equal(2)
	assert_that(c.enabled_combos).is_equal(Array([], TYPE_STRING, "", null))


func test_eval_weights_have_matching_phase_keys() -> void:
	var w: Dictionary = BotConfig.kaiju().kaiju_eval_weights
	assert_that(w.keys()).contains_exactly_in_any_order(["early", "mid", "late"])
	var early_keys: Array = w["early"].keys()
	early_keys.sort()
	for phase in ["mid", "late"]:
		var keys: Array = w[phase].keys()
		keys.sort()
		assert_that(keys).is_equal(early_keys)
