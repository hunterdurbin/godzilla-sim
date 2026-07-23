extends GdUnitTestSuite

## Tier B cluster: cards that <Destroy> opponent battle/strategy cards by rank
## cap or board scope, driven through the real trigger-dispatch seam
## (effect_handler.trigger_* → registry → trigger_map → effect script →
## DestructionEngine). See classification.md for cluster membership.
##
## Conventions: the card under test belongs to player 0; the opponent is
## players[1]; destroyed cards land in players[1].discard_pile (owner of the
## destroyed card). Zone arrays are 0-indexed; monster_zone is 1-indexed.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


## Place the real card in play for player 0 and build the wired session.
## opts (all optional):
##   p0_rage / p0_monster_zone / p0_strategies / p0_discard / p0_monster_stack
##   opp_rage / opp_monster_zone / opp_zone_cards (idx -> card) / opp_strategies
##   card_zone: zone index for a battle card under test (default 2)
func _setup(card_id: String, opts: Dictionary = {}) -> Dictionary:
	var card := Real.instance(card_id)
	var state := States.make_state({
		"p0": {
			"rage": opts.get("p0_rage", 0),
			"monster_zone": opts.get("p0_monster_zone", 1),
			"strategy_zones": opts.get("p0_strategies", []),
		},
		"p1": {
			"rage": opts.get("opp_rage", 0),
			"monster_zone": opts.get("opp_monster_zone", 1),
			"zone_cards": opts.get("opp_zone_cards", {}),
			"strategy_zones": opts.get("opp_strategies", []),
		},
	})
	for c: Dictionary in opts.get("p0_discard", []):
		state.players[0].discard_pile.append(c)
	for c: Dictionary in opts.get("p0_monster_stack", []):
		state.players[0].monster_stack.append(c)
	match int(card.get("card_type", -1)):
		CardEnums.CardType.MONSTER:
			state.players[0].current_monster = card
		CardEnums.CardType.BATTLE:
			state.players[0].push_zone_card(int(opts.get("card_zone", 2)), card)
		CardEnums.CardType.STRATEGY:
			var idx: int = state.players[0].get_first_empty_strategy_zone_index()
			state.players[0].strategy_zones[idx] = card
	var session := States.make_session(state)
	session["state"] = state
	session["card"] = card
	return session


## Fire the trigger entry point a card's destroy effect hangs off.
func _fire(s: Dictionary, trigger: String) -> void:
	var handler: EffectHandler = s["effect_handler"]
	var state: GameState = s["state"]
	match trigger:
		"enter":
			await handler.trigger_enter(0, s["card"])
		"invading":
			# Card must already be players[0].current_monster (see _setup).
			state.players[0].monster_zone = 2
			await handler.trigger_when_invading(0, 1, 2)
		"counter":
			await handler.trigger_counter_success(0, 1)
		"hand_discard":
			var discarded := Cards.battle(2, 3000, "DISC-TRIGGER")
			state.players[0].discard_pile.append(discarded)
			await handler.trigger_hand_card_discarded(0, discarded)


## Board-state options that satisfy (or deliberately fail) a card's condition.
func _condition_opts(cond: String) -> Dictionary:
	match cond:
		"rank1_strategy":
			return {"p0_strategies": [Cards.strategy(1, "COND-R1S")]}
		"strategy_rank2":
			return {"p0_strategies": [Cards.strategy(2, "COND-R2S")]}
		"base":
			return {"p0_strategies": [_base_strategy()]}
		"colors3":
			return {"p0_discard": [
				_colored_battle(CardEnums.CardColor.RED, "DIS-R"),
				_colored_battle(CardEnums.CardColor.BLUE, "DIS-B"),
				_colored_battle(CardEnums.CardColor.GREEN, "DIS-G"),
			]}
		"colors2":
			return {"p0_discard": [
				_colored_battle(CardEnums.CardColor.RED, "DIS-R"),
				_colored_battle(CardEnums.CardColor.BLUE, "DIS-B"),
			]}
		"opp_rage1":
			return {"opp_rage": 1}
		"second_form_one_strategy":
			return {
				"p0_monster_stack": [Cards.monster(2, 8000, [CardEnums.CardTrait.SECOND_FORM], "STACK-2F")],
				"p0_strategies": [Cards.strategy(2, "COND-S")],
			}
		"one_strategy_no_second_form":
			return {
				"p0_monster_stack": [Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "STACK-NO2F")],
				"p0_strategies": [Cards.strategy(2, "COND-S")],
			}
		"rage1_zone4":
			return {"p0_rage": 1, "p0_monster_zone": 4}
	return {}


func _base_strategy() -> Dictionary:
	var s := Cards.strategy(2, "COND-BASE")
	s["is_base"] = true
	return s


func _colored_battle(color: int, id: String) -> Dictionary:
	var c := Cards.battle(2, 3000, id)
	c["colors"] = [color]
	return c


func _opp_discard_has(state: GameState, card: Dictionary) -> bool:
	for c in state.players[1].discard_pile:
		if c.get("id", "") == card.get("id", ""):
			return true
	return false


# --- Single target with a rank cap ---


func test_destroys_single_target_under_rank_cap(card_id: String, cap: int, cond: String, trigger: String,
		test_parameters := [
			["EBP01-040", 7, "", "enter"],
			["EBP01-041", 4, "", "invading"],
			["EBP02-004", 6, "second_form_one_strategy", "enter"],
			["EBP03-020", 7, "base", "counter"],
			["EBP04-003", 6, "rank1_strategy", "enter"],
			["EBP04-015", 6, "", "hand_discard"],
			["EBP04-034", 5, "colors3", "enter"],
			["ESD01-006", 4, "", "enter"],
			["ESD02-002", 4, "", "enter"],
		]) -> void:
	var capped := Cards.battle(cap, 3000, "OPP-CAPPED")
	var above := Cards.battle(cap + 1, 3000, "OPP-ABOVE")
	var opts := _condition_opts(cond)
	opts["opp_zone_cards"] = {1: capped, 4: above}
	var s := _setup(card_id, opts)
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [1]}

	await _fire(s, trigger)

	assert_bool(_opp_discard_has(state, capped)) \
		.override_failure_message("%s: rank-%d card should be destroyed into opponent discard" % [card_id, cap]) \
		.is_true()
	assert_bool(state.players[1].zone_has_cards(1)) \
		.override_failure_message("%s: destroyed card should leave zone idx 1" % card_id).is_false()
	assert_str(state.players[1].get_zone_top_card(4).get("id", "")) \
		.override_failure_message("%s: rank-%d card (above cap) must survive" % [card_id, cap + 1]) \
		.is_equal(above["id"])
	assert_bool(_opp_discard_has(state, above)).is_false()
	# Exactly one zone prompt, whose valid list excludes the above-cap zone.
	assert_int(input.count_calls("select_zone")) \
		.override_failure_message("%s: expected exactly one select_zone prompt" % card_id).is_equal(1)
	for c in input.calls:
		if c["kind"] == "select_zone":
			assert_array(c["valid"]) \
				.override_failure_message("%s: select_zone valid list %s should target only the capped zone" % [card_id, c["valid"]]) \
				.contains_exactly([1])


# --- Single target capped by board position (EBP02-018) ---


func test_ebp02_018_destroys_zone_at_or_before_monster_zone() -> void:
	# Monster in zone 4 with rage 2: only opponent zones 1-4 are targetable,
	# regardless of the targets' ranks.
	var in_range := Cards.battle(6, 3000, "OPP-IN")    # zone 3 (idx 2)
	var out_range := Cards.battle(2, 3000, "OPP-OUT")  # zone 7 (idx 6)
	var s := _setup("EBP02-018", {
		"p0_rage": 2,
		"p0_monster_zone": 4,
		"opp_zone_cards": {2: in_range, 6: out_range},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [2]}

	await _fire(s, "enter")

	assert_bool(_opp_discard_has(state, in_range)).is_true()
	assert_str(state.players[1].get_zone_top_card(6).get("id", "")).is_equal(out_range["id"])
	assert_int(input.count_calls("select_zone")).is_equal(1)
	for c in input.calls:
		if c["kind"] == "select_zone":
			assert_array(c["valid"]) \
				.override_failure_message("EBP02-018: zones past the monster zone must not be targetable: %s" % [c["valid"]]) \
				.contains_exactly([2])


# --- One destroy per strategy in play (EBP02-004) ---


func test_ebp02_004_destroys_one_per_strategy_in_play() -> void:
	var t1 := Cards.battle(6, 3000, "OPP-T1")
	var t2 := Cards.battle(6, 3000, "OPP-T2")
	var above := Cards.battle(7, 3000, "OPP-ABOVE")
	var s := _setup("EBP02-004", {
		"p0_monster_stack": [Cards.monster(2, 8000, [CardEnums.CardTrait.SECOND_FORM], "STACK-2F")],
		"p0_strategies": [Cards.strategy(2, "COND-SA"), Cards.strategy(2, "COND-SB")],
		"opp_zone_cards": {0: t1, 3: t2, 5: above},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zones": [[0, 3]]}

	await _fire(s, "enter")

	assert_bool(_opp_discard_has(state, t1)).is_true()
	assert_bool(_opp_discard_has(state, t2)).is_true()
	assert_str(state.players[1].get_zone_top_card(5).get("id", "")).is_equal(above["id"])
	# One batch prompt for both destroys, count = strategies in play.
	assert_int(input.count_calls("select_zones")).is_equal(1)
	var zone_calls: Array = input.calls.filter(func(c: Dictionary) -> bool: return c["kind"] == "select_zones")
	assert_array(zone_calls[0]["valid"]).contains_exactly_in_any_order([0, 3])
	assert_int(int(zone_calls[0]["count"])).is_equal(2)


# --- Destroy all in a fixed zone band ---


func test_destroys_all_in_fixed_zone_band(card_id: String, inside: Array, outside: Array,
		test_parameters := [
			["EBP01-065", [0, 2, 4], [5, 7]],  # zones 1-5
			["EBP04-083", [5, 6, 7], [0, 4]],  # zones 6-8
		]) -> void:
	var opp_zone_cards := {}
	for zi: int in inside + outside:
		opp_zone_cards[zi] = Cards.battle(3, 3000, "OPP-Z%d" % zi)
	var s := _setup(card_id, {"opp_zone_cards": opp_zone_cards})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await _fire(s, "enter")

	for zi: int in inside:
		assert_bool(state.players[1].zone_has_cards(zi)) \
			.override_failure_message("%s: zone idx %d is in scope and should be destroyed" % [card_id, zi]) \
			.is_false()
		assert_bool(_opp_discard_has(state, opp_zone_cards[zi])).is_true()
	for zi: int in outside:
		assert_str(state.players[1].get_zone_top_card(zi).get("id", "")) \
			.override_failure_message("%s: zone idx %d is out of scope and must survive" % [card_id, zi]) \
			.is_equal(opp_zone_cards[zi]["id"])
	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[1].discard_pile.size()).is_equal(inside.size())


# --- Destroy all in the monster's column (180-degree mirrored boards) ---


func test_destroys_all_in_monster_column(card_id: String,
		test_parameters := [
			["EBP03-072"],
			["EBP04-084"],
			["ESD01-007"],
			["ESD01-016"],
			["EPR-004"],
			["EPR-005"],
			["EPR-014"],
		]) -> void:
	# Own monster in zone 8 (idx 7) → opponent column is zones 3 and 8.
	var inside: Array[int] = CardEffect.get_opponent_column_zones(7)
	assert_array(inside).contains_exactly_in_any_order([2, 7])
	var outside_idx := 3
	var opp_zone_cards := {}
	for zi: int in inside:
		opp_zone_cards[zi] = Cards.battle(3, 3000, "OPP-Z%d" % zi)
	opp_zone_cards[outside_idx] = Cards.battle(3, 3000, "OPP-OUT")
	var s := _setup(card_id, {"p0_monster_zone": 8, "opp_zone_cards": opp_zone_cards})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await _fire(s, "enter")

	for zi: int in inside:
		assert_bool(state.players[1].zone_has_cards(zi)) \
			.override_failure_message("%s: column zone idx %d should be destroyed" % [card_id, zi]) \
			.is_false()
		assert_bool(_opp_discard_has(state, opp_zone_cards[zi])).is_true()
	assert_str(state.players[1].get_zone_top_card(outside_idx).get("id", "")) \
		.override_failure_message("%s: off-column zone idx %d must survive" % [card_id, outside_idx]) \
		.is_equal(opp_zone_cards[outside_idx]["id"])
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- Destroy all adjacent to the opponent's monster (EBP04-020) ---


func test_ebp04_020_destroys_adjacent_to_opponent_monster_with_base() -> void:
	# Opponent monster in zone 4 (idx 3) → adjacent zones idx 2, 4, 6.
	var opp_zone_cards := {}
	for zi: int in [2, 4, 6, 0]:
		opp_zone_cards[zi] = Cards.battle(3, 3000, "OPP-Z%d" % zi)
	var s := _setup("EBP04-020", {
		"p0_strategies": [_base_strategy()],
		"opp_monster_zone": 4,
		"opp_zone_cards": opp_zone_cards,
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await _fire(s, "enter")

	for zi: int in [2, 4, 6]:
		assert_bool(state.players[1].zone_has_cards(zi)) \
			.override_failure_message("EBP04-020: zone idx %d adjacent to opp monster should be destroyed" % zi) \
			.is_false()
	assert_str(state.players[1].get_zone_top_card(0).get("id", "")).is_equal(opp_zone_cards[0]["id"])
	assert_int(state.players[1].discard_pile.size()).is_equal(3)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- Choose a zone, destroy it and its adjacents (optional rank cap) ---


func test_destroys_chosen_zone_and_adjacent(card_id: String, max_rank: int,
		test_parameters := [
			["EBP01-029", 5],
			["ESD02-015", -1],
		]) -> void:
	# Choose zone idx 3 (zone 4): adjacent zones idx 2, 4, 6.
	var target := Cards.battle(5, 3000, "OPP-TARGET")    # idx 3, in scope
	var adj_in := Cards.battle(5, 3000, "OPP-ADJ-IN")    # idx 2, in scope
	var adj_above := Cards.battle(6, 3000, "OPP-ADJ-R6") # idx 6, in scope, above cap 5
	var far := Cards.battle(3, 3000, "OPP-FAR")          # idx 0, out of scope
	var s := _setup(card_id, {"opp_zone_cards": {3: target, 2: adj_in, 6: adj_above, 0: far}})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [3]}

	await _fire(s, "enter")

	assert_bool(_opp_discard_has(state, target)) \
		.override_failure_message("%s: chosen zone should be destroyed" % card_id).is_true()
	assert_bool(_opp_discard_has(state, adj_in)) \
		.override_failure_message("%s: adjacent in-cap card should be destroyed" % card_id).is_true()
	var above_destroyed := max_rank < 0
	assert_bool(_opp_discard_has(state, adj_above)) \
		.override_failure_message("%s: adjacent rank-6 card destroyed=%s expected=%s (cap %d)" % [card_id, _opp_discard_has(state, adj_above), above_destroyed, max_rank]) \
		.is_equal(above_destroyed)
	assert_str(state.players[1].get_zone_top_card(0).get("id", "")) \
		.override_failure_message("%s: non-adjacent zone must survive" % card_id).is_equal(far["id"])
	assert_int(input.count_calls("select_zone")).is_equal(1)


# --- Lowest zones, one per discard color (EBP04-035) ---


func test_ebp04_035_destroys_lowest_zones_up_to_discard_color_count() -> void:
	# 2 colors among battle cards in own discard → destroy the 2 lowest-numbered
	# occupied opponent zones, no player choice involved.
	var low1 := Cards.battle(3, 3000, "OPP-LOW1")
	var low2 := Cards.battle(7, 3000, "OPP-LOW2")  # rank irrelevant for this card
	var high := Cards.battle(2, 3000, "OPP-HIGH")
	var s := _setup("EBP04-035", {
		"p0_discard": [
			_colored_battle(CardEnums.CardColor.RED, "DIS-R"),
			_colored_battle(CardEnums.CardColor.BLUE, "DIS-B"),
		],
		"opp_zone_cards": {1: low1, 4: low2, 6: high},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await _fire(s, "enter")

	assert_bool(_opp_discard_has(state, low1)).is_true()
	assert_bool(_opp_discard_has(state, low2)).is_true()
	assert_str(state.players[1].get_zone_top_card(6).get("id", "")) \
		.override_failure_message("EBP04-035: third occupied zone exceeds the 2-color budget and must survive") \
		.is_equal(high["id"])
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- Strategy destroy (EBP04-074) ---


func test_ebp04_074_destroys_chosen_opponent_strategy() -> void:
	var strat_a := Cards.strategy(2, "OPP-STRAT-A")
	var strat_b := Cards.strategy(3, "OPP-STRAT-B")
	var s := _setup("EBP04-074", {"opp_strategies": [strat_a, strat_b]})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_strategy": [1]}

	await _fire(s, "enter")

	assert_bool(state.players[1].strategy_zones[1].is_empty()) \
		.override_failure_message("EBP04-074: chosen strategy zone should be emptied").is_true()
	assert_bool(_opp_discard_has(state, strat_b)).is_true()
	assert_str(state.players[1].strategy_zones[0].get("id", "")) \
		.override_failure_message("EBP04-074: unchosen strategy must survive").is_equal(strat_a["id"])
	assert_int(input.count_calls("select_strategy")).is_equal(1)
	for c in input.calls:
		if c["kind"] == "select_strategy":
			assert_array(c["valid"]).contains_exactly_in_any_order([0, 1])


func test_ebp04_074_no_opponent_strategy_destroys_nothing() -> void:
	var bystander := Cards.battle(1, 3000, "OPP-BYSTANDER")
	var s := _setup("EBP04-074", {"opp_zone_cards": {1: bystander}})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await _fire(s, "enter")

	assert_int(input.count_calls("select_strategy")).is_equal(0)
	assert_int(state.players[1].discard_pile.size()).is_equal(0)
	assert_str(state.players[1].get_zone_top_card(1).get("id", "")).is_equal(bystander["id"])


# --- Condition not met → nothing destroyed ---


func test_condition_not_met_destroys_nothing(card_id: String, cond: String, trigger: String,
		test_parameters := [
			["EBP02-004", "one_strategy_no_second_form", "enter"],  # no <2nd Form> under
			["EBP02-018", "rage1_zone4", "enter"],                  # rage < 2
			["EBP03-020", "strategy_rank2", "counter"],             # no <Base> in play
			["EBP04-003", "strategy_rank2", "enter"],               # no rank-1 strategy
			["EBP04-015", "opp_rage1", "hand_discard"],             # opponent rage != 0
			["EBP04-020", "strategy_rank2", "enter"],               # no <Base> in play
			["EBP04-034", "colors2", "enter"],                      # < 3 discard colors
			["EBP04-035", "", "enter"],                             # 0 discard colors
		]) -> void:
	# A rank-1 card adjacent to / before everything: destroyable by every card
	# in this table if its condition were met.
	var bystander := Cards.battle(1, 3000, "OPP-BYSTANDER")
	var opts := _condition_opts(cond)
	opts["opp_zone_cards"] = {1: bystander}
	var s := _setup(card_id, opts)
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [1]}

	await _fire(s, trigger)

	assert_str(state.players[1].get_zone_top_card(1).get("id", "")) \
		.override_failure_message("%s: condition unmet — opponent card must survive" % card_id) \
		.is_equal(bystander["id"])
	assert_int(state.players[1].discard_pile.size()) \
		.override_failure_message("%s: condition unmet — opponent discard must stay empty" % card_id) \
		.is_equal(0)
	assert_int(input.count_calls("select_zone")) \
		.override_failure_message("%s: condition unmet — no zone prompt expected" % card_id) \
		.is_equal(0)
