extends GdUnitTestSuite

## MaxCounterOptimizer: the deck builder's "Maximum Counter Power" search.
## Entries are deck-builder-shaped ({card_number, quantity}); every expected
## total is what the real engine reports for the optimizer's winning board.

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


func _zone_base_ids(result: Dictionary) -> Array:
	var ids := []
	for zone in result["zones"]:
		if not zone.is_empty():
			ids.append(CardUtils.base_id(zone))
	return ids


func test_top_seven_of_available_battle_cards() -> void:
	# 8 copies of 5000 + 4 of 1000: only 7 zones exist, best 7 are all 5000s.
	var result := _run([], [
		_entry(VANILLA_5K, 4), _entry(VANILLA_5K_B, 4), _entry(VANILLA_1K, 4),
	])
	assert_int(result["total_cp"]).is_equal(35000)
	assert_int(_zone_base_ids(result).size()).is_equal(7)


func test_small_deck_places_everything() -> void:
	var result := _run([], [_entry(VANILLA_5K, 2), _entry(VANILLA_1K, 1)])
	assert_int(result["total_cp"]).is_equal(11000)


func test_empty_deck_reports_zero() -> void:
	var result := _run([], [])
	assert_int(result["total_cp"]).is_equal(0)
	assert_array(_zone_base_ids(result)).is_empty()


func test_adjacency_cards_land_next_to_monster() -> void:
	# EBP01-025 King Caesar: +3000 while adjacent to your monster (4000 base).
	# A monster zone with three neighbors lets all three copies get the bonus:
	# 3 x 7000 + 4 x 5000 = 41000.
	var result := _run([_entry("EBP02-052", 1)], [
		_entry("EBP01-025", 3), _entry(VANILLA_5K, 4),
	])
	assert_int(result["total_cp"]).is_greater_equal(41000)
	var monster_idx: int = result["monster_zone"] - 1
	var adjacent := CardEffect.get_adjacent_zones(monster_idx)
	for i in range(8):
		var zone: Dictionary = result["zones"][i]
		if not zone.is_empty() and CardUtils.base_id(zone) == "EBP01-025":
			assert_bool(i in adjacent) \
				.override_failure_message("EBP01-025 in zone idx %d not adjacent to monster idx %d" % [i, monster_idx]) \
				.is_true()


func test_adjacency_cards_win_contested_adjacent_slots() -> void:
	# Placement-free 10000 tokens (2x EBP02-077 -> T04) must NOT squat on the
	# monster-adjacent slots the King Caesars need: the optimum parks all
	# three EBP01-025 adjacent (3 x 7000) and the tokens elsewhere
	# (2 x 10000), leaving two vanilla 5000s — 51000 total. The naive
	# solo-score greedy would seed tokens into adjacent slots and stall at
	# 47000; the sensitive-first seed order finds the trade.
	var result := _run([], [
		_entry("EBP02-077", 2), _entry("EBP02-012", 2),
		_entry("EBP01-025", 3), _entry(VANILLA_5K, 4),
	])
	assert_int(result["total_cp"]).is_equal(51000)


func test_strategy_flat_bonus_counted_with_four_battle_cards() -> void:
	# EBP02-017 Operation Taba: <Your Turn> +5000 with 4+ battle cards.
	var with_four := _run([], [_entry("EBP02-017", 1), _entry(VANILLA_1K, 4)])
	assert_int(with_four["total_cp"]).is_equal(4000 + 5000)
	var with_three := _run([], [_entry("EBP02-017", 1), _entry(VANILLA_1K, 3)])
	assert_int(with_three["total_cp"]).is_equal(3000)


func test_token_upgrade_replaces_generator() -> void:
	# EBP02-077 Chibi Godzilla (5000) self-replaces with EBP02-T04 (10000)
	# when a <Godzilla> card is milled — EBP02-012 (0 CP) is the witness and
	# must stay in the deck, so T04 alone (10000) beats fielding 077 + 012.
	var result := _run([], [_entry("EBP02-077", 1), _entry("EBP02-012", 1)])
	assert_int(result["total_cp"]).is_equal(10000)
	var ids := _zone_base_ids(result)
	assert_array(ids).contains(["EBP02-T04"])
	assert_array(ids).not_contains(["EBP02-077"])
	assert_array(ids).not_contains(["EBP02-012"])


func test_token_upgrade_needs_godzilla_in_deck() -> void:
	# A lone 077 has no other <Godzilla> card to mill: stays a 5000 body.
	# (077 itself carries the trait, but the fielded copy can't mill itself.)
	var result := _run([], [_entry("EBP02-077", 1)])
	assert_int(result["total_cp"]).is_equal(5000)
	assert_array(_zone_base_ids(result)).not_contains(["EBP02-T04"])


func test_token_upgrade_mill_witness_is_consumed() -> void:
	# Two lone copies: one transform consumes the other copy as its mill
	# witness, so a second token OR fielding the witness alongside the token
	# is impossible — the ceiling is a single 10000 body, not 15000.
	var result := _run([], [_entry("EBP02-077", 2)])
	assert_int(result["total_cp"]).is_equal(10000)


func test_token_upgrade_spare_witness_can_be_fielded() -> void:
	# Two witnesses available (2x EBP02-012): one feeds the mill, so the
	# other may still be fielded as a body alongside the token.
	var result := _run([], [_entry("EBP02-077", 1), _entry("EBP02-012", 2)])
	assert_int(result["total_cp"]).is_equal(10000)
	assert_array(_zone_base_ids(result)).contains(["EBP02-T04", "EBP02-012"])


func test_zone_filler_tokens_fill_leftover_zones() -> void:
	# EBP02-020 with 5 other strategies in the deck fills every empty zone
	# with 2000-CP Train Bombers. All five 017s must sit in the discard as
	# the fill's witnesses, so NONE may be fielded — 7 x 2000, no +5000.
	var result := _run([], [_entry("EBP02-020", 1), _entry("EBP02-017", 5)])
	assert_int(result["total_cp"]).is_equal(7 * 2000)
	assert_array(_zone_base_ids(result)).contains(["EBP02-T01"])
	# The played 020 may legitimately occupy a slot; the five 017 witnesses
	# must all stay in the discard.
	for sz in result["strategies"]:
		assert_bool(sz.is_empty() or CardUtils.base_id(sz) == "EBP02-020") \
			.override_failure_message("a fill witness was fielded: %s" % sz.get("id", "")) \
			.is_true()


func test_zone_filler_gated_on_strategy_count() -> void:
	# Only 4 other strategies: the fill never happens.
	var result := _run([], [_entry("EBP02-020", 1), _entry("EBP02-017", 4)])
	assert_int(result["total_cp"]).is_equal(0)


func test_linked_token_requires_generator_on_board() -> void:
	# EBP04-067 Godzilla Earth (9000) plays a linked 9000 token into zone 3;
	# both bodies count while the generator stays on the board.
	var result := _run([], [_entry("EBP04-067", 1)])
	assert_int(result["total_cp"]).is_equal(18000)
	assert_str(CardUtils.base_id(result["zones"][2])).is_equal("EBP04-T01")
	assert_array(_zone_base_ids(result)).contains(["EBP04-067"])


func test_rage_conditional_assumed_reachable() -> void:
	# EBP02-011 Gabara: 2000 base, +3000 with 2+ rage — max assumes the rage.
	var result := _run([], [_entry("EBP02-011", 1)])
	assert_int(result["total_cp"]).is_equal(5000)
	assert_int(result["rage"]).is_greater_equal(2)


func test_vanilla_only_deck_reports_zero_rage() -> void:
	var result := _run([], [_entry(VANILLA_5K, 1)])
	assert_int(result["rage"]).is_equal(0)


func test_deterministic_across_runs() -> void:
	var monster_entries := [_entry("EBP02-052", 1)]
	var main_entries := [
		_entry("EBP01-025", 2), _entry(VANILLA_5K, 3), _entry("EBP02-011", 2),
		_entry("EBP02-017", 2), _entry("EBP02-077", 1), _entry(VANILLA_1K, 4),
	]
	var first := _run(monster_entries, main_entries)
	var second := _run(monster_entries, main_entries)
	assert_int(second["total_cp"]).is_equal(first["total_cp"])
	assert_int(second["monster_zone"]).is_equal(first["monster_zone"])
	assert_array(_zone_base_ids(second)).is_equal(_zone_base_ids(first))


func _fielded_ids(result: Dictionary) -> Array:
	var ids := []
	for zone in result["zones"]:
		if not zone.is_empty():
			ids.append(zone["id"])
	for sz in result["strategies"]:
		if not sz.is_empty():
			ids.append(sz["id"])
	var unders: Dictionary = result.get("unders", {})
	for slot in unders:
		ids.append(unders[slot]["id"])
	return ids


func test_duplicate_copies_not_inflated() -> void:
	# ESD01-010 grants field CP to zone 8 per copy — exactly the shape that
	# made the buggy improve pass clone one instance across zones.
	var result := _run([], [_entry("ESD01-010", 3), _entry(VANILLA_5K, 4)])
	var ids := _fielded_ids(result)
	var seen := {}
	var base_counts := {}
	for id in ids:
		assert_bool(seen.has(id)) \
			.override_failure_message("instance %s fielded twice" % id).is_false()
		seen[id] = true
		var base: String = id.substr(0, id.find("_"))
		base_counts[base] = base_counts.get(base, 0) + 1
	assert_int(base_counts.get("ESD01-010", 0)).is_less_equal(3)

	# EBP03-067's variable base scales per copy — 1 in deck means 1 on board.
	var single := _run([], [_entry("EBP03-067", 1), _entry(VANILLA_5K, 2), _entry(VANILLA_5K_B, 2)])
	var count := 0
	for id in _fielded_ids(single):
		if id.begins_with("EBP03-067"):
			count += 1
	assert_int(count).is_equal(1)


func test_ebp04_067_only_fields_in_zone_8() -> void:
	# "This card can only be played in zone 8" — the body locks to idx 7
	# (its linked token keeps idx 2).
	var result := _run([], [_entry("EBP04-067", 4), _entry(VANILLA_5K, 4)])
	for i in range(8):
		var zone: Dictionary = result["zones"][i]
		if not zone.is_empty() and CardUtils.base_id(zone) == "EBP04-067":
			assert_int(i).override_failure_message(
				"EBP04-067 fielded in zone idx %d (only idx 7 is legal)" % i).is_equal(7)


func test_ebp04_067_unfieldable_when_monster_pinned_to_zone_8() -> void:
	var result := _run([], [_entry("EBP04-067", 1)], {"monster_zone": 8})
	assert_array(_zone_base_ids(result)).not_contains(["EBP04-067", "EBP04-T01"])
	assert_int(result["monster_zone"]).is_equal(8)


func test_two_identical_base_strategies_stack() -> void:
	# EBP04-082 grants +3000 to each NON-BLUE battle card adjacent to the
	# monster; two copies (one per strategy slot) legally stack to +6000.
	# 3 green Megalons adjacent: 3x5000 + 2x(3x3000) = 33000. (EBP01-053 is
	# blue — 082 would skip it.)
	var result := _run([], [_entry("EBP04-082", 2), _entry(VANILLA_5K_B, 3)])
	assert_int(result["total_cp"]).is_equal(33000)
	for sz in result["strategies"]:
		assert_str(CardUtils.base_id(sz)).is_equal("EBP04-082")


func test_ebp03_064_gets_under_card_with_awakening() -> void:
	# Mothra(imago): 6000 base, +3000@Awakening4 +3000@Awakening6 only with
	# a card under it (its Enter tucks any battle card from the discard).
	# 064 + 6 fielded vanillas + 1 tucked spare: 12000 + 6000 = 18000.
	var result := _run([], [_entry("EBP03-064", 1), _entry(VANILLA_1K, 8)])
	assert_int(result["total_cp"]).is_equal(18000)
	var found := false
	for i in range(8):
		var zone: Dictionary = result["zones"][i]
		if not zone.is_empty() and CardUtils.base_id(zone) == "EBP03-064":
			found = result["unders"].has(i)
	assert_bool(found).override_failure_message("EBP03-064 fielded without an under-card").is_true()
	assert_int(result["monster_zone"]).is_greater_equal(6)


func test_ebp01_026_under_requires_gigan_fest() -> void:
	# Jet Jaguar(2023): +5000 with a <Gigan>+<Fest> card under it. Tucking
	# the only EBP01-072 beats fielding it (12000+30000 > 37000).
	var with_gigan := _run([], [
		_entry("EBP01-026", 1), _entry("EBP01-072", 1), _entry(VANILLA_5K, 6),
	])
	assert_int(with_gigan["total_cp"]).is_equal(42000)
	# Without a qualifying card no under is attached.
	var without := _run([], [_entry("EBP01-026", 1), _entry(VANILLA_5K, 6)])
	assert_int(without["total_cp"]).is_equal(7000 + 30000)
	assert_bool(without["unders"].is_empty()).is_true()


func test_ebp03_051_stacks_on_little_godzilla() -> void:
	# Godzilla Jr. (6000, +5000 per under) may stack onto LITTLE_GODZILLA
	# tops: tucking EBP04-048 (4000) yields 11000 > 10000 fielded apart.
	var result := _run([], [_entry("EBP03-051", 1), _entry("EBP04-048", 1)])
	assert_int(result["total_cp"]).is_equal(11000)
	var tucked := false
	for slot in result["unders"]:
		tucked = CardUtils.base_id(result["unders"][slot]) == "EBP04-048"
	assert_bool(tucked).is_true()


func test_ebp04_043_strategy_tuck_costs_slot() -> void:
	# MFS-3: +10000 with an invasion-icon-2 strategy tucked from the
	# strategy zone: 7000 + 10000 beats 7000 + an idle strategy slot.
	var result := _run([], [_entry("EBP04-043", 1), _entry("EBP04-077", 1)])
	assert_int(result["total_cp"]).is_equal(17000)
	var strategy_unders := 0
	for slot in result["unders"]:
		if result["unders"][slot].get("card_type") == CardEnums.CardType.STRATEGY:
			strategy_unders += 1
	var filled := 0
	for sz in result["strategies"]:
		if not sz.is_empty():
			filled += 1
	assert_int(strategy_unders).is_equal(1)
	assert_bool(strategy_unders + filled <= 2).is_true()


func test_crystal_tokens_feed_ebp02_072_flat_bonus() -> void:
	# EBP02-072: +20000 total CP with 3+ Crystals (EBP02-T03, 0 CP). The
	# SpaceGodzilla monsters generate 6 token candidates. With MORE than 7
	# plain bodies competing for the slots (like the real deck), only the
	# tokens-first seed fields the 0-CP enablers — their solo score is 0 and
	# single replace swaps can't build the pile. Strategies then pick both
	# 072 copies and the replace pass trims the crystals back to exactly 3:
	# 4x5000 + 3x0 + 2x20000 = 60000 (vs 35000 for seven bodies).
	var result := _run([
		_entry("EBP02-052", 1), _entry("EBP02-053", 1),
		_entry("EBP02-054", 1), _entry("EBP02-057", 1),
	], [
		_entry(VANILLA_5K_B, 4), _entry(VANILLA_5K, 4), _entry("EBP02-072", 2),
	])
	assert_int(result["total_cp"]).is_equal(60000)
	var crystals := 0
	for base in _zone_base_ids(result):
		if base == "EBP02-T03":
			crystals += 1
	assert_int(crystals).override_failure_message(
		"expected 3+ Crystals fielded, got %d" % crystals).is_greater_equal(3)
	for sz in result["strategies"]:
		assert_str(CardUtils.base_id(sz)).is_equal("EBP02-072")


func test_mothra_deck_fields_all_ebp03_064_copies() -> void:
	# Regression ("03 - Mothra" decklist bug): all three 6000-printed 064s
	# must field with tucked eggs at 12000 each — scored bare they tied the
	# underless seed comparison and two copies lost their slots to plain
	# 6000 bodies. 3x12000 + 3x10000 (054) + 6000 (050) = 72000.
	var result := _run([_entry("EBP03-022", 1)], [
		_entry("EBP03-064", 3), _entry("EBP03-054", 3),
		_entry("EBP03-050", 3), _entry("EBP01-044", 3),
	])
	assert_int(result["total_cp"]).is_equal(72000)
	var copies := 0
	for base in _zone_base_ids(result):
		if base == "EBP03-064":
			copies += 1
	assert_int(copies).override_failure_message(
		"expected all 3 EBP03-064 copies fielded, got %d" % copies).is_equal(3)
	assert_int(result["unders"].size()).is_equal(3)
	assert_int(result["monster_zone"]).is_greater_equal(6)


func test_evolves_under_requires_matching_trait_and_rank() -> void:
	# Evolution as an under source: EBP03-044 (Evolution7 MOTHRA) may sit
	# under the rank-7 MOTHRA 064; the Evolution5 egg may not (rank), nor may
	# a LITTLE_GODZILLA evolution card sit under GODZILLA_JR-trait 051
	# (trait), nor a card without evolution fields at all.
	var optimizer := MaxCounterOptimizer.new()
	var top := Real.instance("EBP03-064")
	assert_bool(optimizer._evolves_under(top, Real.instance("EBP03-044"))).is_true()
	assert_bool(optimizer._evolves_under(top, Real.instance("EBP01-044"))).is_false()
	assert_bool(optimizer._evolves_under(top, Real.instance("EBP03-054"))).is_false()
	assert_bool(optimizer._evolves_under(
		Real.instance("EBP03-051"), Real.instance("EBP02-030"))).is_false()
	optimizer.teardown()


func test_evolution_under_skips_strategy_slot_accounting() -> void:
	# An evolution-qualified under never came from a strategy zone, so it
	# must not consume one of the 2 strategy slots (unlike EBP04-043's own
	# strategy-sourced tucks). No current evolution card matches a
	# stack-source top's traits while its filter rejects it, so the under is
	# synthetic — this exercises the validity split, not an engine total.
	var optimizer := MaxCounterOptimizer.new()
	var evo_under := {
		"id": "TEST-EVO_0_0", "card_type": CardEnums.CardType.BATTLE,
		"rank": 1, "traits": [], "counter_power": 0,
		"evolution_rank": 8,
		"evolution_trait": CardEnums.CardTrait.MECHAGODZILLA,
	}
	var zones: Array = [{}, Real.instance("EBP04-043"), {}, {}, {}, {}, {}, {}]
	var assignment := {
		"monster": {}, "monster_zone": 1, "zones": zones,
		"strategies": [Real.instance("EBP02-017", 0), Real.instance("EBP02-017", 1)],
		"rage": 0, "opp_monster_zone": 1,
		"unders": {1: evo_under},
	}
	assert_bool(optimizer._board_valid(assignment)).is_true()
	# The same full-slot board with a strategy-sourced under is over budget.
	assignment["unders"] = {1: Real.instance("EBP04-077")}
	assert_bool(optimizer._board_valid(assignment)).is_false()
	optimizer.teardown()


func test_fixed_rage_zero_disables_rage_bonus() -> void:
	var result := _run([], [_entry("EBP02-011", 1)], {"rage": 0})
	assert_int(result["total_cp"]).is_equal(2000)
	assert_int(result["rage"]).is_equal(0)


func test_fixed_opp_zone_drives_column_bonus() -> void:
	# EBP02-016 Anguirus(2004): 7000, +5000 while in the same column as the
	# opponent's monster.
	var pinned := _run([], [_entry("EBP02-016", 1)], {"opp_monster_zone": 3})
	assert_int(pinned["total_cp"]).is_equal(12000)
	assert_int(pinned["opp_monster_zone"]).is_equal(3)
	# Any: the sweep finds a matching opponent zone by itself.
	var any_zone := _run([], [_entry("EBP02-016", 1)])
	assert_int(any_zone["total_cp"]).is_equal(12000)
	assert_bool(any_zone["opp_monster_zone"] >= 1 and any_zone["opp_monster_zone"] <= 8).is_true()


func test_fixed_monster_zone_restricts_configs() -> void:
	# EBP02-033: 3000 base, +3000 at Awakening4 (monster_zone >= 4).
	var pinned := _run([], [_entry("EBP02-033", 1)], {"monster_zone": 1})
	assert_int(pinned["total_cp"]).is_equal(3000)
	assert_int(pinned["monster_zone"]).is_equal(1)
	var free := _run([], [_entry("EBP02-033", 1)])
	assert_int(free["total_cp"]).is_equal(6000)


func test_all_under_dependent_cp_cards_have_stack_sources() -> void:
	## Guard: every effect whose CP virtuals read the zone stack under it
	## must be modeled in STACK_SOURCES, or the preview under-reports.
	## Keyed on the CP-side read (tuck APIs vary: place_card_under_zone,
	## direct zones[i].append, stacks_on_play). Dev-only (reads sources).
	var registry := EffectRegistry.new()
	var missing: Array[String] = []
	var dir := DirAccess.open("res://scripts/effects")
	assert_object(dir).is_not_null()
	for set_dir in dir.get_directories():
		var set_path := "res://scripts/effects/%s" % set_dir
		for file in DirAccess.get_files_at(set_path):
			if not file.ends_with(".gd"):
				continue
			var path := "%s/%s" % [set_path, file]
			var probe := {"effect_script": path}
			var has_cp := false
			for method in MaxCounterOptimizer.CP_TRIGGERS:
				if registry.has_trigger(probe, method):
					has_cp = true
					break
			if not has_cp:
				continue
			var source := FileAccess.get_file_as_string(path)
			if "get_cards_under_top(" not in source and "get_zone_stack(" not in source:
				continue
			var stem := file.get_basename()
			var base_id := stem.substr(0, stem.rfind("_")).to_upper() + "-" + stem.substr(stem.rfind("_") + 1)
			if not MaxCounterOptimizer.STACK_SOURCES.has(base_id):
				missing.append(base_id)
	assert_array(missing) \
		.override_failure_message("Under-dependent CP cards missing from STACK_SOURCES: %s" % [missing]) \
		.is_empty()


func test_every_cp_effect_evaluates_on_synthetic_state() -> void:
	## Smoke: every card whose effect touches counter power must survive
	## evaluation on the synthetic board (catches effects that dereference
	## opponent/flow state the deck-analysis harness leaves minimal).
	var registry := EffectRegistry.new()
	for id in Real.ids_with_effects():
		var card := Real.instance(id)
		var has_cp := false
		for method in MaxCounterOptimizer.CP_TRIGGERS:
			if registry.has_trigger(card, method):
				has_cp = true
				break
		if not has_cp:
			continue
		var pool: Array[Dictionary] = [card]
		var mcs: MaxCounterState
		var zones: Array = [{}, {}, {}, {}, {}, {}, {}, {}]
		var strategies: Array = [{}, {}]
		var monster: Dictionary = {}
		match card.get("card_type"):
			CardEnums.CardType.BATTLE:
				mcs = MaxCounterState.new(pool, [])
				zones[1] = card
			CardEnums.CardType.STRATEGY:
				mcs = MaxCounterState.new(pool, [])
				strategies[0] = card
			CardEnums.CardType.MONSTER:
				mcs = MaxCounterState.new([] as Array[Dictionary], pool)
				monster = card
			_:
				continue
		mcs.apply({"monster": monster, "monster_zone": 1, "zones": zones,
			"strategies": strategies, "rage": 10})
		var total := mcs.evaluate()
		assert_bool(total >= -100000) \
			.override_failure_message("%s produced nonsense total %d" % [id, total]) \
			.is_true()
		mcs.teardown()


func test_all_token_generators_have_token_source_entries() -> void:
	## Guard: every effect script that creates tokens must be modeled in
	## TOKEN_SOURCES, or the max-CP preview silently under-reports. Dev-only
	## (reads effect sources from disk).
	var missing: Array[String] = []
	var dir := DirAccess.open("res://scripts/effects")
	assert_object(dir).is_not_null()
	for set_dir in dir.get_directories():
		var set_path := "res://scripts/effects/%s" % set_dir
		for file in DirAccess.get_files_at(set_path):
			if not file.ends_with(".gd"):
				continue
			var source := FileAccess.get_file_as_string("%s/%s" % [set_path, file])
			if "create_token_in_zone(" not in source and "create_tokens_in_zones(" not in source:
				continue
			# ebp02_020.gd -> EBP02-020
			var stem := file.get_basename()
			var base_id := stem.substr(0, stem.rfind("_")).to_upper() + "-" + stem.substr(stem.rfind("_") + 1)
			if not MaxCounterOptimizer.TOKEN_SOURCES.has(base_id):
				missing.append(base_id)
	assert_array(missing) \
		.override_failure_message("Token generators missing from MaxCounterOptimizer.TOKEN_SOURCES: %s" % [missing]) \
		.is_empty()
