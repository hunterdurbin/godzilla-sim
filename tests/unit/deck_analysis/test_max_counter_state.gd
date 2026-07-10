extends GdUnitTestSuite

## MaxCounterState: the synthetic counter-phase board the deck builder's
## "Maximum Counter Power" preview evaluates. Every total is read back
## through CounterResolver.compute_counter_numbers on a real GameState —
## these tests pin the harness contract the optimizer relies on.

const Cards := preload("res://tests/fixtures/cards.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _vanilla_pool(cps: Array) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for i in range(cps.size()):
		pool.append(Cards.battle(2, cps[i], "T-BTL-%d" % i))
	return pool


func _zones_with(cards: Array, monster_zone: int) -> Array:
	## Lay cards into zone slots left to right, skipping the monster's index.
	var zones: Array = []
	zones.resize(8)
	zones.fill({})
	var monster_idx := monster_zone - 1
	var next := 0
	for card in cards:
		while next == monster_idx:
			next += 1
		zones[next] = card
		next += 1
	return zones


func test_seven_vanillas_sum_printed_cp() -> void:
	var pool := _vanilla_pool([6000, 5000, 5000, 4000, 3000, 2000, 1000])
	var mcs := MaxCounterState.new(pool, [Cards.monster(1)])
	mcs.apply({
		"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with(pool, 1), "strategies": [{}, {}], "rage": 0,
	})
	assert_int(mcs.evaluate()).is_equal(26000)
	mcs.teardown()


func test_unplaced_copies_land_in_discard() -> void:
	var pool := _vanilla_pool([6000, 5000, 4000])
	var mcs := MaxCounterState.new(pool, [])
	mcs.apply({
		"monster": {}, "monster_zone": 1,
		"zones": _zones_with([pool[0]], 1), "strategies": [{}, {}], "rage": 0,
	})
	assert_int(mcs.evaluate()).is_equal(6000)
	assert_int(mcs.state.players[0].discard_pile.size()).is_equal(2)
	assert_int(mcs.state.players[0].hand.size()).is_equal(0)
	assert_int(mcs.state.players[0].main_deck.size()).is_equal(0)
	mcs.teardown()


func test_reapply_rewrites_board() -> void:
	var pool := _vanilla_pool([6000, 5000])
	var mcs := MaxCounterState.new(pool, [])
	mcs.apply({"monster": {}, "monster_zone": 1,
		"zones": _zones_with([pool[0]], 1), "strategies": [{}, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(6000)
	mcs.apply({"monster": {}, "monster_zone": 1,
		"zones": _zones_with([pool[1]], 1), "strategies": [{}, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(5000)
	assert_int(mcs.state.players[0].discard_pile.size()).is_equal(1)
	mcs.teardown()


func test_rage_conditional_counts_with_rage() -> void:
	# EBP02-011 Gabara: +3000 while your monster has 2 or more Rage.
	var card := Real.instance("EBP02-011")
	var pool: Array[Dictionary] = [card]
	var mcs := MaxCounterState.new(pool, [Cards.monster(1)])
	var base: int = card.get("counter_power", 0)
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with([card], 1), "strategies": [{}, {}], "rage": 2})
	assert_int(mcs.evaluate()).is_equal(base + 3000)
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with([card], 1), "strategies": [{}, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(base)
	mcs.teardown()


func test_awakening_conditional_follows_monster_zone() -> void:
	# EBP01-018: +3000 at Awakening4 (monster_zone >= 4).
	var card := Real.instance("EBP01-018")
	var pool: Array[Dictionary] = [card]
	var mcs := MaxCounterState.new(pool, [Cards.monster(1)])
	var base: int = card.get("counter_power", 0)
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 4,
		"zones": _zones_with([card], 4), "strategies": [{}, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(base + 3000)
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with([card], 1), "strategies": [{}, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(base)
	mcs.teardown()


func test_strategy_flat_modifier_needs_four_battle_cards() -> void:
	# EBP02-017 Operation Taba: <Your Turn> +5000 total CP with 4+ battle
	# cards — the COUNTER-phase perspective is the counterer's own turn.
	var strategy := Real.instance("EBP02-017")
	var battles := _vanilla_pool([1000, 1000, 1000, 1000])
	var pool: Array[Dictionary] = battles.duplicate()
	pool.append(strategy)
	var mcs := MaxCounterState.new(pool, [Cards.monster(1)])
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with(battles, 1), "strategies": [strategy, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(4000 + 5000)
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 1,
		"zones": _zones_with(battles.slice(0, 3), 1), "strategies": [strategy, {}], "rage": 0})
	assert_int(mcs.evaluate()).is_equal(3000)
	mcs.teardown()


func test_monster_stack_built_from_lower_ranks() -> void:
	var monsters := Cards.monster_line()
	var mcs := MaxCounterState.new([] as Array[Dictionary], monsters)
	mcs.apply({"monster": monsters[3], "monster_zone": 5,
		"zones": _zones_with([], 5), "strategies": [{}, {}], "rage": 0})
	var player: PlayerState = mcs.state.players[0]
	assert_int(player.monster_stack.size()).is_equal(3)
	# Descending rank: directly-below first (rank 3, 2, 1).
	assert_int(player.monster_stack[0].get("rank", 0)).is_equal(3)
	assert_int(player.monster_stack[2].get("rank", 0)).is_equal(1)
	assert_int(player.monster_deck.size()).is_equal(0)
	mcs.teardown()


func test_breakdown_reports_per_zone_cp() -> void:
	var card := Real.instance("EBP01-018")  # +3000 at Awakening4
	var vanilla := Cards.battle(2, 4000, "T-VAN")
	var pool: Array[Dictionary] = [card, vanilla]
	var mcs := MaxCounterState.new(pool, [Cards.monster(1)])
	mcs.apply({"monster": Cards.monster(1), "monster_zone": 8,
		"zones": _zones_with([card, vanilla], 8), "strategies": [{}, {}], "rage": 0})
	var data := mcs.breakdown()
	var base: int = card.get("counter_power", 0)
	assert_int(data["total_cp"]).is_equal(mcs.evaluate())
	assert_int(data["zone_mods"][0]).is_equal(3000)
	assert_int(data["zone_cp"][0]).is_equal(base + 3000)
	assert_int(data["zone_cp"][1]).is_equal(4000)
	assert_int(data["zone_cp"][2]).is_equal(0)
	mcs.teardown()


func test_apply_places_under_card_and_opp_zone() -> void:
	var top := Cards.battle(2, 5000, "T-TOP")
	var under := Cards.battle(1, 1000, "T-UNDER")
	var spare := Cards.battle(1, 2000, "T-SPARE")
	var pool: Array[Dictionary] = [top, under, spare]
	var mcs := MaxCounterState.new(pool, [])
	mcs.apply({"monster": {}, "monster_zone": 1,
		"zones": _zones_with([top], 1), "strategies": [{}, {}], "rage": 0,
		"opp_monster_zone": 5, "unders": {1: under}})
	var player: PlayerState = mcs.state.players[0]
	assert_int(player.zones[1].size()).is_equal(2)
	assert_str(player.get_zone_top_card(1).get("id", "")).is_equal("T-TOP")
	assert_str(player.zones[1][1].get("id", "")).is_equal("T-UNDER")
	# Under is consumed from the pool: only the spare lands in the discard.
	assert_int(player.discard_pile.size()).is_equal(1)
	assert_str(player.discard_pile[0].get("id", "")).is_equal("T-SPARE")
	assert_int(mcs.state.players[1].monster_zone).is_equal(5)
	# Only the TOP card's counter power counts.
	assert_int(mcs.evaluate()).is_equal(5000)
	mcs.teardown()


func test_teardown_is_idempotent() -> void:
	var mcs := MaxCounterState.new([] as Array[Dictionary], [])
	mcs.teardown()
	mcs.teardown()
	assert_object(mcs.effect_handler).is_null()
	assert_object(mcs.action_handler).is_null()
