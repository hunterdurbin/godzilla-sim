extends GdUnitTestSuite

## Tier B cluster: stat_modifier cards whose passive getters alter counter
## power — self CP, monster CP, field CP, total CP, and opponent doubling.
## Every assertion goes through the EffectQueries aggregation layer
## (get_effective_zone_cp / get_monster_cp_modifier / get_counter_power_modifier),
## never by calling the effect's getter directly, and each scenario asserts
## both the firing and the non-firing state of the card's condition.
## See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _wire(state: GameState) -> EffectHandler:
	return States.make_session(state)["effect_handler"]


func _battle_colored(color: int, id: String, rank: int = 2, cp: int = 3000) -> Dictionary:
	var card := Cards.battle(rank, cp, id)
	card["colors"] = [color]
	return card


## A Crystals token as the engine creates it (bare template id, TOKEN trait).
func _crystal(copy: int) -> Dictionary:
	var token := Real.instance("EBP02-T03", copy)
	token["id"] = "EBP02-T03"
	return token


# --- Self CP modifiers (battle card in a zone) ---


func test_cp_in_zone8(card_id: String, base_cp: int,
		test_parameters := [
			["EBP01-017", 1000],
			["EBP02-034", 5000],
			["EBP02-061", 4000],
		]) -> void:
	var card := Real.instance(card_id)
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 7)) \
		.override_failure_message("%s: +3000 CP while in zone 8" % card_id) \
		.is_equal(base_cp + 3000)

	state.players[0].clear_zone(7)
	state.players[0].push_zone_card(2, card)
	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: base CP outside zone 8" % card_id) \
		.is_equal(base_cp)


func test_cp_awakening(card_id: String, base_cp: int, threshold: int,
		test_parameters := [
			["EBP01-018", 1000, 4],
			["EBP01-067", 1000, 4],
			["EBP02-033", 3000, 4],
			["ESD01-009", 2000, 4],
			["EBP01-046", 1000, 6],
			["EBP02-066", 8000, 6],
			["ESD02-011", 5000, 6],
		]) -> void:
	var card := Real.instance(card_id)
	var state := States.make_state({"p0": {"zone_cards": {0: card}, "monster_zone": threshold}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: +3000 CP at Awakening%d" % [card_id, threshold]) \
		.is_equal(base_cp + 3000)

	state.players[0].monster_zone = threshold - 1
	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: base CP below Awakening%d" % [card_id, threshold]) \
		.is_equal(base_cp)


func test_cp_rage_at_least_2(card_id: String, base_cp: int,
		test_parameters := [
			["EBP01-023", 4000],
			["EBP02-011", 2000],
		]) -> void:
	var card := Real.instance(card_id)
	var state := States.make_state({"p0": {"zone_cards": {0: card}, "rage": 2}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: +3000 CP with rage 2" % card_id) \
		.is_equal(base_cp + 3000)

	state.players[0].rage = 1
	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: base CP with rage 1" % card_id) \
		.is_equal(base_cp)


func test_cp_adjacent_to_monster(card_id: String, base_cp: int,
		test_parameters := [
			["EBP01-025", 4000],
			["EBP01-068", 1000],
			["EBP02-076", 3000],
			["EBP03-045", 2000],
			["EBP04-058", 2000],  # also requires Awakening4 — monster_zone 4 satisfies it
		]) -> void:
	# Monster at zone 4 (idx 3): adjacent zones are idx 2, 4, 6.
	var card := Real.instance(card_id)
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 4}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: +3000 CP adjacent to own monster" % card_id) \
		.is_equal(base_cp + 3000)

	state.players[0].clear_zone(2)
	state.players[0].push_zone_card(0, card)  # idx 0 adjacency = [1], not adjacent to idx 3
	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: base CP away from own monster" % card_id) \
		.is_equal(base_cp)


func test_cp_adjacent_requires_awakening4_ebp04_058() -> void:
	# Adjacent (idx 1 next to monster idx 2) but monster only in zone 3 → no bonus.
	var card := Real.instance("EBP04-058")
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "monster_zone": 3}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 1)) \
		.override_failure_message("EBP04-058: adjacency alone must not fire below Awakening4") \
		.is_equal(2000)

	state.players[0].monster_zone = 4  # idx 3, adjacent to idx 1? no — adjacency of 1 is [0, 2]
	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(2, card)  # idx 2 adjacent to idx 3
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)


func test_cp_opp_monster_same_column(card_id: String, base_cp: int, bonus: int,
		test_parameters := [
			["EBP02-016", 7000, 5000],
			["EBP03-056", 2000, 3000],
			["EBP04-065", 5000, 3000],
		]) -> void:
	# Card at idx 2 (zone 3) faces opponent zones 3 and 8 → opp monster_zone 3 is in column.
	var card := Real.instance(card_id)
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: bonus while opp monster is in same column" % card_id) \
		.is_equal(base_cp + bonus)

	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: base CP when opp monster leaves the column" % card_id) \
		.is_equal(base_cp)


func test_cp_same_column_colored_monster_awakening4(card_id: String, base_cp: int, color_name: String,
		test_parameters := [
			["EBP04-069", 2000, "blue"],
			["EBP04-070", 3000, "green"],
			["EBP04-071", 4000, "red"],
		]) -> void:
	var color: int
	match color_name:
		"red": color = CardEnums.CardColor.RED
		"blue": color = CardEnums.CardColor.BLUE
		"green": color = CardEnums.CardColor.GREEN
	var card := Real.instance(card_id)
	var opp_monster := Cards.monster()
	opp_monster["colors"] = [color]
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "monster_zone": 4},
		"p1": {"monster_zone": 3, "current_monster": opp_monster},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: +5000 CP vs %s monster in column at Awakening4" % [card_id, color_name]) \
		.is_equal(base_cp + 5000)

	# Wrong monster color → no bonus.
	opp_monster["colors"] = [CardEnums.CardColor.WHITE]
	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: base CP vs wrong-color monster" % card_id) \
		.is_equal(base_cp)

	# Right color but below Awakening4 → no bonus.
	opp_monster["colors"] = [color]
	state.players[0].monster_zone = 3
	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("%s: base CP below Awakening4" % card_id) \
		.is_equal(base_cp)


func test_cp_same_zone_number_as_opp_monster_ebp02_015() -> void:
	var card := Real.instance("EBP02-015")
	var state := States.make_state({
		"p0": {"zone_cards": {4: card}},  # zone 5
		"p1": {"monster_zone": 5},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(4000 + 3000)

	state.players[1].monster_zone = 4
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(4000)


func test_cp_per_opp_rage_in_column_ebp01_056() -> void:
	var card := Real.instance("EBP01-056")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3, "rage": 2},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 2)) \
		.override_failure_message("EBP01-056: +3000 per opp rage while in column") \
		.is_equal(5000 + 6000)

	state.players[1].rage = 0
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)

	state.players[1].rage = 2
	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)


func test_cp_opp_rank_and_column_esd02_012() -> void:
	var card := Real.instance("ESD02-012")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3, "current_monster": Cards.monster(4)},
	})
	var handler := _wire(state)

	# Both conditions: +5000 (rank IV) +3000 (column).
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000 + 8000)

	# Column only.
	state.players[1].current_monster = Cards.monster(1)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000 + 3000)

	# Rank only.
	state.players[1].current_monster = Cards.monster(4)
	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000 + 5000)

	# Neither.
	state.players[1].current_monster = Cards.monster(1)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)


func test_cp_named_card_in_play(card_id: String, base_cp: int, required_name: String, bonus: int,
		test_parameters := [
			["EBP01-074", 8000, "Gravity Beam", 20000],
			["EBP04-060", 3000, "Mechagodzilla City", 3000],
		]) -> void:
	var card := Real.instance(card_id)
	var named := Cards.strategy(2, "T-NAMED")
	named["name"] = required_name
	var state := States.make_state({
		"p0": {"zone_cards": {0: card}, "strategy_zones": [named]},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: bonus while '%s' is in play" % [card_id, required_name]) \
		.is_equal(base_cp + bonus)

	state.players[0].strategy_zones[0] = {}
	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: base CP without '%s'" % [card_id, required_name]) \
		.is_equal(base_cp)


func test_cp_ride_card_in_discard_epr_015() -> void:
	var card := Real.instance("EPR-015")
	var state := States.make_state({"p0": {"zone_cards": {0: card}}})
	state.players[0].discard_pile.append(
		Cards.battle(2, 2000, "RIDE-1", [CardEnums.CardTrait.GODZILLA_THE_RIDE]))
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(4000 + 5000)

	state.players[0].discard_pile.pop_back()
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(4000)


func test_cp_monsters_in_discard_ebp01_051() -> void:
	var card := Real.instance("EBP01-051")
	var state := States.make_state({"p0": {"zone_cards": {0: card}}})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-M%d" % i))
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(3000 + 3000)

	state.players[0].discard_pile.pop_back()
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(3000)


func test_cp_monster_stack_5_ebp03_065() -> void:
	var card := Real.instance("EBP03-065")
	var state := States.make_state({"p0": {"zone_cards": {0: card}}})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "STK-%d" % i))
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(7000 + 3000)

	state.players[0].monster_stack.resize(4)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(7000)


func test_cp_awakening6_stack_tiers_ebp02_065() -> void:
	var card := Real.instance("EBP02-065")
	var state := States.make_state({"p0": {"zone_cards": {0: card}, "monster_zone": 6}})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "STK-%d" % i))
	var handler := _wire(state)

	# 5+ under → +10000.
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000 + 10000)

	# 3-4 under → +5000.
	state.players[0].monster_stack.resize(3)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000 + 5000)

	# 2 under → base.
	state.players[0].monster_stack.resize(2)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000)

	# 5 under but below Awakening6 → base.
	for i in range(3):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "STK-X%d" % i))
	state.players[0].monster_zone = 5
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000)


func test_cp_two_other_battle_cards(card_id: String, base_cp: int,
		test_parameters := [
			["EBP04-038", 2000],
			["EBP02-031", 2000],  # the 2 others must be rank ≤ 5 — fixture rank 2 qualifies
		]) -> void:
	var card := Real.instance(card_id)
	var state := States.make_state({"p0": {"zone_cards": {
		0: card,
		1: Cards.battle(2, 3000, "OTH-1"),
		2: Cards.battle(2, 3000, "OTH-2"),
	}}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: +3000 CP with 2 other battle cards" % card_id) \
		.is_equal(base_cp + 3000)

	state.players[0].clear_zone(2)
	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("%s: base CP with only 1 other battle card" % card_id) \
		.is_equal(base_cp)


func test_cp_non_green_battle_ebp04_057() -> void:
	var card := Real.instance("EBP04-057")
	var state := States.make_state({"p0": {"zone_cards": {
		0: card,
		1: _battle_colored(CardEnums.CardColor.RED, "RED-1"),
	}}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(2000 + 3000)

	# Alone (the card itself is green and must not satisfy its own condition).
	state.players[0].clear_zone(1)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(2000)


func test_cp_rank1_strategy_in_play_ebp04_037() -> void:
	var card := Real.instance("EBP04-037")
	var state := States.make_state({
		"p0": {"zone_cards": {0: card}, "strategy_zones": [Cards.strategy(1, "STR-R1")]},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(2000 + 3000)

	state.players[0].strategy_zones[0] = Cards.strategy(2, "STR-R2")
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(2000)


func test_cp_strategy_count_difference_ebp04_054() -> void:
	var card := Real.instance("EBP04-054")
	var state := States.make_state({
		"p0": {
			"zone_cards": {0: card},
			"strategy_zones": [Cards.strategy(1, "OWN-1"), Cards.strategy(2, "OWN-2")],
		},
		"p1": {"strategy_zones": [Cards.strategy(1, "OPP-1")]},
	})
	var handler := _wire(state)

	# +5000 × 2 own − 5000 × 1 opp.
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000 + 5000)

	# 1 own / 1 opp → net zero.
	state.players[0].strategy_zones[1] = {}
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000)

	# 0 own / 2 opp → −10000.
	state.players[0].strategy_zones[0] = {}
	state.players[1].strategy_zones[1] = Cards.strategy(2, "OPP-2")
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000 - 10000)


func test_cp_opp_has_godzilla_ebp02_067() -> void:
	var card := Real.instance("EBP02-067")
	# Default fixture monster carries the GODZILLA trait → condition fires.
	var state := States.make_state({"p0": {"zone_cards": {0: card}}})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000 + 5000)

	# Opp monster without GODZILLA and no Godzilla battle card → base.
	state.players[1].current_monster = Cards.monster(1, 5000, [CardEnums.CardTrait.RODAN], "OPP-MON")
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000)

	# A Godzilla battle card in the opponent's zones also fires it.
	state.players[1].push_zone_card(3, Cards.battle(2, 3000, "OPP-GZ", [CardEnums.CardTrait.GODZILLA]))
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000 + 5000)


# --- Monster-card CP modifiers (get_monster_cp_modifier) ---


func test_monster_cp_zone_ge_opponent_ebp04_017() -> void:
	var state := States.make_state({
		"p0": {"current_monster": Real.instance("EBP04-017"), "monster_zone": 3},
		"p1": {"monster_zone": 3},
	})
	var handler := _wire(state)

	assert_int(handler.get_monster_cp_modifier(0)) \
		.override_failure_message("EBP04-017: +5000 total CP when own zone >= opp zone") \
		.is_equal(5000)

	state.players[1].monster_zone = 4
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)


func test_monster_cp_zone_ge_and_discard_ebp04_019() -> void:
	var state := States.make_state({
		"p0": {"current_monster": Real.instance("EBP04-019"), "monster_zone": 4},
		"p1": {"monster_zone": 1},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-M%d" % i))
	var handler := _wire(state)

	assert_int(handler.get_monster_cp_modifier(0)).is_equal(10000)

	state.players[0].discard_pile.pop_back()
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)


func test_monster_cp_fest_adjacent_efc01_001() -> void:
	# Monster at zone 1 (idx 0): only adjacent zone is idx 1.
	var state := States.make_state({
		"p0": {
			"current_monster": Real.instance("EFC01-001"),
			"monster_zone": 1,
			"zone_cards": {1: Cards.battle(2, 3000, "FEST-1", [CardEnums.CardTrait.FEST])},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_monster_cp_modifier(0)) \
		.override_failure_message("EFC01-001: +10000 when every adjacent zone has a FEST battle card") \
		.is_equal(10000)

	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(1, Cards.battle(2, 3000, "PLAIN-1"))
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)


# --- Field CP modifiers (+X to OTHER zones, via get_effective_zone_cp) ---


func test_field_cp_adjacent_rank5_ebp02_021() -> void:
	# Monster at zone 1 (idx 0): adjacent = idx 1.
	var state := States.make_state({
		"p0": {
			"current_monster": Real.instance("EBP02-021"),
			"monster_zone": 1,
			"zone_cards": {
				1: Cards.battle(2, 3000, "ADJ"),
				4: Cards.battle(2, 3000, "FAR"),
			},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 1)) \
		.override_failure_message("EBP02-021: +3000 to rank<=5 battle adjacent to monster") \
		.is_equal(3000 + 3000)
	assert_int(handler.get_effective_zone_cp(0, 4)) \
		.override_failure_message("EBP02-021: non-adjacent zone unaffected") \
		.is_equal(3000)

	# Rank 6 adjacent card is not buffed.
	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(1, Cards.battle(6, 3000, "ADJ-R6"))
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)


func test_field_cp_adjacent_ebp02_041() -> void:
	var state := States.make_state({
		"p0": {
			"current_monster": Real.instance("EBP02-041"),
			"monster_zone": 1,
			"zone_cards": {
				1: Cards.battle(2, 3000, "ADJ"),
				4: Cards.battle(2, 3000, "FAR"),
			},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000 + 1000)
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(3000)


func test_field_cp_adjacent_per_stack_ebp02_043() -> void:
	var state := States.make_state({
		"p0": {
			"current_monster": Real.instance("EBP02-043"),
			"monster_zone": 1,
			"zone_cards": {1: Cards.battle(2, 3000, "ADJ")},
		},
	})
	state.players[0].monster_stack.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GIGAN], "U-1"))
	state.players[0].monster_stack.append(Cards.monster(2, 7000, [CardEnums.CardTrait.GIGAN], "U-2"))
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 1)) \
		.override_failure_message("EBP02-043: +1000 per card under the monster, to adjacent zones") \
		.is_equal(3000 + 2000)

	state.players[0].monster_stack.clear()
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)


func test_field_cp_strategy_nonblue_adjacent_ebp04_082() -> void:
	var state := States.make_state({
		"p0": {
			"strategy_zones": [Real.instance("EBP04-082")],
			"monster_zone": 1,
			"zone_cards": {
				1: _battle_colored(CardEnums.CardColor.RED, "ADJ-RED"),
				4: _battle_colored(CardEnums.CardColor.RED, "FAR-RED"),
			},
		},
	})
	var handler := _wire(state)

	# <Your Turn>: current_player_id defaults to 0 (= owner's turn).
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000 + 3000)
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(3000)

	# Blue battle cards are excluded.
	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(1, _battle_colored(CardEnums.CardColor.BLUE, "ADJ-BLUE"))
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)

	# Off-turn the effect is dormant.
	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(1, _battle_colored(CardEnums.CardColor.RED, "ADJ-RED2"))
	state.current_player_id = 1
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)


# --- Total CP modifiers (strategy get_total_cp_modifier, via get_counter_power_modifier) ---


func test_total_cp_destoroyah_own_turn_ebp01_062() -> void:
	var state := States.make_state({
		"p0": {
			"strategy_zones": [Real.instance("EBP01-062")],
			"zone_cards": {0: Cards.battle(2, 3000, "DST", [CardEnums.CardTrait.DESTOROYAH])},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_counter_power_modifier(0)).is_equal(10000)

	state.current_player_id = 1
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)

	state.current_player_id = 0
	state.players[0].clear_zone(0)
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)


func test_total_cp_four_battles_own_turn_ebp02_017() -> void:
	var state := States.make_state({
		"p0": {
			"strategy_zones": [Real.instance("EBP02-017")],
			"zone_cards": {
				0: Cards.battle(2, 3000, "B-0"),
				1: Cards.battle(2, 3000, "B-1"),
				2: Cards.battle(2, 3000, "B-2"),
				3: Cards.battle(2, 3000, "B-3"),
			},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_counter_power_modifier(0)).is_equal(5000)

	state.players[0].clear_zone(3)
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)


func test_total_cp_crystals_own_turn_ebp02_072() -> void:
	var state := States.make_state({
		"p0": {
			"strategy_zones": [Real.instance("EBP02-072")],
			"zone_cards": {0: _crystal(0), 1: _crystal(1), 2: _crystal(2)},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_counter_power_modifier(0)).is_equal(20000)

	state.players[0].clear_zone(2)
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)


# --- Opponent column doubling (EBP02-029) ---


func test_opp_column_cp_doubled_ebp02_029() -> void:
	# P1's monster (card owner) at zone 5 (idx 4) → doubles P0's zones in
	# column 5 (cross-board: P0 idx 0). Active from counter phase on P0's turn.
	var state := States.make_state({
		"p0": {"zone_cards": {
			0: Cards.battle(2, 5000, "COL"),
			3: Cards.battle(2, 4000, "OFF-COL"),
		}},
		"p1": {"current_monster": Real.instance("EBP02-029"), "monster_zone": 5},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var handler := _wire(state)

	assert_int(handler.get_effective_zone_cp(0, 0)) \
		.override_failure_message("EBP02-029: column CP doubled during counter phase") \
		.is_equal(10000)
	assert_int(handler.get_effective_zone_cp(0, 3)) \
		.override_failure_message("EBP02-029: off-column zone unaffected") \
		.is_equal(4000)

	# Before the counter phase nothing is doubled.
	state.current_phase = CardEnums.GamePhase.MAIN
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000)

	# On the card owner's own turn nothing is doubled.
	state.current_phase = CardEnums.GamePhase.COUNTER
	state.current_player_id = 1
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000)
