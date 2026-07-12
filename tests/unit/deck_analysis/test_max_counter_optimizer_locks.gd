extends GdUnitTestSuite

## MaxCounterOptimizer live-board locks (the bot's KaijuCounterOracle path):
## locked cards are fixed occupants — never moved, evicted, swapped, or
## tucked over — and every reported total still comes off the real engine.
## Empty lock params must reproduce the unconstrained v1 search exactly.

const Real := preload("res://tests/fixtures/real_cards.gd")

# Real vanilla battle cards (no effect_script):
const VANILLA_5K := "EBP01-053"
const VANILLA_5K_B := "EBP02-063"
const VANILLA_1K := "EBP01-016"


func _entry(id: String, qty: int) -> Dictionary:
	return {"card_number": id, "quantity": qty}


func _run(monster_entries: Array, main_entries: Array, params: Dictionary = {}) -> Dictionary:
	var optimizer := MaxCounterOptimizer.new()
	var result := optimizer.run(monster_entries, main_entries, params)
	optimizer.teardown()
	return result


func test_locked_zone_survives_replace_and_relocate() -> void:
	# A locked 1000 body in zone idx 0 with eight 5000s competing: the six
	# remaining free slots (monster pinned to zone 8 occupies idx 7) take
	# 5000s and the lock survives every replace/relocate attempt —
	# 1000 + 6x5000 = 31000 (the same deck unlocked fields 35000).
	var locked := Real.instance(VANILLA_1K)
	var result := _run([], [_entry(VANILLA_5K, 4), _entry(VANILLA_5K_B, 4)], {
		"monster_zone": 8, "rage": 0,
		"locked_zones": {0: locked},
	})
	assert_int(result["total_cp"]).is_equal(31000)
	assert_str(CardUtils.base_id(result["zones"][0])).is_equal(VANILLA_1K)
	# The locked copy was re-stamped into the collision-proof namespace.
	assert_str(result["zones"][0]["id"]).contains("_lk_")


func test_locked_strategy_slot_fixed() -> void:
	# Locked EBP02-017 (+5000 with 4+ battle cards) in strategy slot 0 stays
	# put and its effect counts against the fielded pool bodies.
	var locked := Real.instance("EBP02-017")
	var result := _run([], [_entry(VANILLA_1K, 4)], {
		"rage": 0,
		"locked_strategies": {0: locked},
	})
	assert_int(result["total_cp"]).is_equal(4000 + 5000)
	assert_str(CardUtils.base_id(result["strategies"][0])).is_equal("EBP02-017")


func test_locked_under_preserved() -> void:
	# EBP03-064 (6000; +3000@Awakening4 +3000@Awakening6 with a card under)
	# locked at zone idx 0 with its live under: the tuck survives and both
	# awakenings count at monster zone 8. Empty pool — the board alone scores.
	var result := _run([], [], {
		"monster_zone": 8, "rage": 0,
		"locked_zones": {0: Real.instance("EBP03-064")},
		"locked_unders": {0: Real.instance(VANILLA_1K)},
	})
	assert_int(result["total_cp"]).is_equal(12000)
	assert_bool(result["unders"].has(0)).is_true()
	# The same locked top WITHOUT an under never gets one tucked (the live
	# board can't retroactively tuck): the under bonuses stay dead at 6000.
	var bare := _run([], [], {
		"monster_zone": 8, "rage": 0,
		"locked_zones": {0: Real.instance("EBP03-064")},
	})
	assert_int(bare["total_cp"]).is_equal(6000)
	assert_bool(bare["unders"].is_empty()).is_true()


func test_locked_monster_pins_config() -> void:
	# monster_entries empty + locked_monster: the config loop collapses to
	# the live monster. EBP02-033 (+3000 at Awakening4) reads the pinned zone.
	var result := _run([], [_entry("EBP02-033", 1)], {
		"locked_monster": Real.instance("EBP02-052"),
		"monster_zone": 4, "rage": 0,
	})
	assert_str(CardUtils.base_id(result["monster"])).is_equal("EBP02-052")
	assert_int(result["monster_zone"]).is_equal(4)
	assert_int(result["total_cp"]).is_equal(6000)


func test_empty_pool_scores_locked_board_exactly() -> void:
	var result := _run([], [], {
		"monster_zone": 1, "rage": 0,
		"locked_zones": {1: Real.instance(VANILLA_5K), 2: Real.instance(VANILLA_1K)},
	})
	assert_int(result["total_cp"]).is_equal(6000)


func test_locked_board_plus_pool_fills_free_slots() -> void:
	# The oracle's exact shape: live board locked (zone + strategy), the deck
	# remainder fills free slots, bounded work. 4 battle cards fielded
	# (1 locked + 3 pool) light up the locked 017: 1000 + 3x5000 + 5000.
	var result := _run([], [_entry(VANILLA_5K, 3)], {
		"monster_zone": 8, "rage": 0,
		"locked_zones": {0: Real.instance(VANILLA_1K)},
		"locked_strategies": {0: Real.instance("EBP02-017")},
		"finalists": 1, "improve_passes": 1,
	})
	assert_int(result["total_cp"]).is_equal(21000)


func test_locked_id_collision_with_pool_ids() -> void:
	# Live instance ids share the BASE_x_n shape _expand_entries emits; the
	# _lk_ re-stamp keeps the pool copy fieldable next to its locked twin.
	var locked := Real.instance(VANILLA_1K)
	locked["id"] = "%s_0_0" % VANILLA_1K  # deliberately collide
	var result := _run([], [_entry(VANILLA_1K, 1)], {
		"monster_zone": 8, "rage": 0,
		"locked_zones": {0: locked},
	})
	assert_int(result["total_cp"]).is_equal(2000)


func test_no_locks_matches_v1() -> void:
	# Regression guard on the lock-aware pass refactors: empty params must
	# reproduce the unconstrained result (test_top_seven scenario).
	var result := _run([], [
		_entry(VANILLA_5K, 4), _entry(VANILLA_5K_B, 4), _entry(VANILLA_1K, 4),
	])
	assert_int(result["total_cp"]).is_equal(35000)


func test_improve_passes_zero_still_finalizes() -> void:
	# Seed-only mode (the oracle's fully-locked degenerate case) still
	# finalizes and reports the greedy-fill board.
	var result := _run([], [_entry(VANILLA_5K, 2), _entry(VANILLA_1K, 1)], {
		"finalists": 1, "improve_passes": 0,
	})
	assert_int(result["total_cp"]).is_equal(11000)
