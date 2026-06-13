extends GdUnitTestSuite

## Tier C bespoke tests for EBP04 cards 001-049 — one-of-a-kind effects driven
## through the real trigger-dispatch seam. See classification.md for the list.
## Part B (050-089 + T01) lives in test_ebp04_bespoke_b.gd.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


## A test battle card with an explicit color (fixture default is RED).
func _colored_battle(rank: int, cp: int, id: String, color: int, traits: Array = []) -> Dictionary:
	var card := Cards.battle(rank, cp, id, traits)
	card["colors"] = [color]
	return card


func _green_battle(rank: int, cp: int, id: String, traits: Array = []) -> Dictionary:
	return _colored_battle(rank, cp, id, CardEnums.CardColor.GREEN, traits)


## The recorded input calls of one kind (reveal acknowledgements shift raw indices).
func _calls(input: ScriptedPlayerInput, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in input.calls:
		if c["kind"] == kind:
			out.append(c)
	return out


# --- EBP04-001: opp counter start, empty monster column → +1 rage ---


func test_ebp04_001_gains_rage_at_opponent_counter_when_column_clear() -> void:
	var monster := Real.instance("EBP04-001")
	# Monster zone 4 (idx 3) → opponent column zones [1].
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster, "monster_zone": 4},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].rage).is_equal(1)


func test_ebp04_001_silent_with_column_card_or_on_own_turn() -> void:
	# Opponent battle card in the column: no gain.
	var monster := Real.instance("EBP04-001")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP-COL")}, "monster_zone": 8},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].rage).is_equal(0)

	# Own turn: TRIGGER_FILTERS gates it off.
	var monster2 := Real.instance("EBP04-001", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2, "monster_zone": 4}})
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP04-002: column card destroyed + rank1 strategy → opp discards to 2 ---


func test_ebp04_002_opponent_discards_to_2_when_column_card_destroyed() -> void:
	var monster := Real.instance("EBP04-002")
	var state := States.make_state({
		"p0": {
			"current_monster": monster, "monster_zone": 4,
			"strategy_zones": [Cards.strategy(1, "S-R1")],
		},
		"p1": {
			"zone_cards": {1: Cards.battle(3, 3000, "OPP-COL")},
			"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1), Cards.battle(1)],
			"monster_zone": 8,
		},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[1], [1])

	assert_int(state.players[1].hand.size()).is_equal(2)


func test_ebp04_002_silent_without_rank1_strategy_or_off_column() -> void:
	# No rank 1 strategy in play: no discard.
	var monster := Real.instance("EBP04-002")
	var state := States.make_state({
		"p0": {
			"current_monster": monster, "monster_zone": 4,
			"strategy_zones": [Cards.strategy(2, "S-R2")],
		},
		"p1": {
			"zone_cards": {1: Cards.battle(3, 3000, "OPP-COL")},
			"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1)],
			"monster_zone": 8,
		},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.destroy_zones(state.players[1], [1])
	assert_int(state.players[1].hand.size()).is_equal(3)

	# Destroyed card outside the monster column: trigger filter blocks it.
	var monster2 := Real.instance("EBP04-002", 1)
	var state2 := States.make_state({
		"p0": {
			"current_monster": monster2, "monster_zone": 4,
			"strategy_zones": [Cards.strategy(1, "S-R1B")],
		},
		"p1": {
			"zone_cards": {4: Cards.battle(3, 3000, "OPP-OFF")},
			"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1)],
			"monster_zone": 8,
		},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.destroy_zones(state2.players[1], [4])
	assert_int(state2.players[1].hand.size()).is_equal(3)


# --- EBP04-004: enter with rank1 strategy in play → +2 rage ---


func test_ebp04_004_enter_gains_2_rage_only_with_rank1_strategy() -> void:
	var monster := Real.instance("EBP04-004")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"strategy_zones": [Cards.strategy(1, "S-R1")],
	}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(state.players[0].rage).is_equal(2)

	var monster2 := Real.instance("EBP04-004", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": monster2,
		"strategy_zones": [Cards.strategy(2, "S-R2")],
	}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, monster2)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP04-005: enter searches rank1 strategy into play; column destroy cascade ---


func test_ebp04_005_enter_searches_rank1_strategy_into_play() -> void:
	var monster := Real.instance("EBP04-005")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"main_deck": [Cards.battle(2, 2000, "D1"), Cards.strategy(1, "S-R1"), Cards.strategy(2, "S-R2")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "S-R1"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_str(str(state.players[0].strategy_zones[0].get("id"))).is_equal("S-R1")
	assert_int(state.players[0].main_deck.size()).is_equal(2)
	# Pool was rank-1-strategy filtered.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp04_005_enter_silent_with_two_strategies_in_play() -> void:
	var monster := Real.instance("EBP04-005")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"strategy_zones": [Cards.strategy(2, "SA"), Cards.strategy(3, "SB")],
		"main_deck": [Cards.strategy(1, "S-R1")],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(1)


func test_ebp04_005_column_destroy_cascades_to_lower_ranks() -> void:
	# NOTE: implementation destroys ALL opponent battle cards with rank <= the
	# destroyed card's rank, not just those in this card's column — see the
	# suspected-bug note in the suite report.
	var monster := Real.instance("EBP04-005")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {
			"zone_cards": {
				1: Cards.battle(4, 3000, "OPP-COL-R4"),
				0: Cards.battle(3, 3000, "OPP-R3"),
				5: Cards.battle(6, 3000, "OPP-R6"),
			},
			"monster_zone": 8,
		},
	})
	for i in range(3):
		state.players[0].discard_pile.append(Cards.strategy(1, "DS%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[1], [1])

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_str(str(p1.get_zone_top_card(5).get("id"))).is_equal("OPP-R6")
	assert_int(p1.discard_pile.size()).is_equal(2)


func test_ebp04_005_no_cascade_below_3_rank1_strategies_in_discard() -> void:
	var monster := Real.instance("EBP04-005")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {
			"zone_cards": {1: Cards.battle(4, 3000, "OPP-COL"), 0: Cards.battle(3, 3000, "OPP-R3")},
			"monster_zone": 8,
		},
	})
	state.players[0].discard_pile.append_array([Cards.strategy(1, "DS0"), Cards.strategy(1, "DS1")])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[1], [1])

	assert_bool(state.players[1].zone_has_cards(0)).is_true()


# --- EBP04-007: Burst 3; Step-1 invasion advances 2 zones ---


func test_ebp04_007_burst_rank_and_step1_advance_bonus() -> void:
	var monster := Real.instance("EBP04-007")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.queries.get_burst_rank(monster)).is_equal(3)
	# Step 1: +1 bonus zone (advances 2 total). Step 2: no bonus.
	assert_int(handler.get_invasion_advance_bonus(0, 1)).is_equal(1)
	assert_int(handler.get_invasion_advance_bonus(0, 2)).is_equal(0)


# --- EBP04-009: opp counter start, discard strategy → destroy column rank<=6 ---


func test_ebp04_009_discards_strategy_to_destroy_column_rank_6_or_less() -> void:
	var monster := Real.instance("EBP04-009")
	# Monster zone 3 (idx 2) → opponent column zones [2, 7].
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"current_monster": monster, "monster_zone": 3,
			"hand": [Cards.strategy(2, "H-STR"), Cards.battle(2, 2000, "H-BTL")],
		},
		"p1": {
			"zone_cards": {
				2: Cards.battle(4, 3000, "OPP-COL-R4"),
				7: Cards.battle(7, 3000, "OPP-COL-R7"),
				0: Cards.battle(2, 3000, "OPP-OFF"),
			},
			"monster_zone": 4,
		},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_str(str(p1.get_zone_top_card(7).get("id"))).is_equal("OPP-COL-R7")  # rank 7 > 6
	assert_str(str(p1.get_zone_top_card(0).get("id"))).is_equal("OPP-OFF")     # off column
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("H-STR")
	# Only the strategy hand index was offered as the cost.
	assert_array(input.calls[0]["valid"]).contains_exactly([0])


func test_ebp04_009_skipping_the_cost_destroys_nothing() -> void:
	var monster := Real.instance("EBP04-009")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster, "monster_zone": 3, "hand": [Cards.strategy(2, "H-STR")]},
		"p1": {"zone_cards": {2: Cards.battle(4, 3000, "OPP-COL")}, "monster_zone": 4},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[1].zone_has_cards(2)).is_true()
	assert_int(state.players[0].hand.size()).is_equal(1)


# --- EBP04-010: rage reset → discard 2 to keep rage at 2 ---


func test_ebp04_010_rage_reset_pays_2_cards_to_keep_rage_2() -> void:
	var monster := Real.instance("EBP04-010")
	var state := States.make_state({"p0": {
		"current_monster": monster, "rage": 3,
		"hand": [Cards.battle(1, 1000, "H1"), Cards.battle(1, 1000, "H2"),
			Cards.battle(1, 1000, "H3"), Cards.battle(1, 1000, "H4")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	var result: int = await handler.apply_rage_reset(0)

	assert_int(result).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(2)
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


func test_ebp04_010_declining_or_failing_conditions_resets_to_0() -> void:
	# Declining the choice: returns 0, hand untouched.
	var monster := Real.instance("EBP04-010")
	var state := States.make_state({"p0": {
		"current_monster": monster, "rage": 2,
		"hand": [Cards.battle(1, 1000, "H1"), Cards.battle(1, 1000, "H2")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(await handler.apply_rage_reset(0)).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(2)

	# Rage below 2: no prompt at all.
	var monster2 := Real.instance("EBP04-010", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": monster2, "rage": 1,
		"hand": [Cards.battle(1, 1000, "H1"), Cards.battle(1, 1000, "H2")],
	}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_int(await handler2.apply_rage_reset(0)).is_equal(0)
	assert_int(input2.count_calls("choose_option")).is_equal(0)

	# Hand smaller than 2: no prompt.
	var monster3 := Real.instance("EBP04-010", 2)
	var state3 := States.make_state({"p0": {
		"current_monster": monster3, "rage": 3, "hand": [Cards.battle(1, 1000, "H1")],
	}})
	var input3 := ScriptedPlayerInput.new()
	var s3 := States.make_session(state3, input3)
	var handler3: EffectHandler = s3["effect_handler"]
	assert_int(await handler3.apply_rage_reset(0)).is_equal(0)
	assert_int(input3.count_calls("choose_option")).is_equal(0)


# --- EBP04-012: alt play cost from rank II Biollante; enter plays Tentacles ---


func test_ebp04_012_can_play_from_rank_2_biollante_with_rank3_in_monster_deck() -> void:
	var card := Real.instance("EBP04-012")
	var biollante := Cards.monster(2, 9000, [CardEnums.CardTrait.BIOLLANTE], "BIO-R2")
	var state := States.make_state({"p0": {
		"current_monster": biollante,
		"monster_deck": [Cards.monster(3, 15000, [CardEnums.CardTrait.BIOLLANTE], "BIO-R3")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.can_monster_be_played_from_hand(0, card)).is_true()

	# Wrong trait on current monster.
	var state2 := States.make_state({"p0": {
		"current_monster": Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "GOJI-R2"),
		"monster_deck": [Cards.monster(3, 15000, [], "M-R3")],
	}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_bool(handler2.can_monster_be_played_from_hand(0, Real.instance("EBP04-012", 1))).is_false()

	# No rank III card left in the monster deck.
	var state3 := States.make_state({"p0": {"current_monster": biollante.duplicate(true)}})
	var s3 := _session(state3)
	var handler3: EffectHandler = s3["effect_handler"]
	assert_bool(handler3.can_monster_be_played_from_hand(0, Real.instance("EBP04-012", 2))).is_false()


func test_ebp04_012_play_cost_stacks_rank3_under_monster() -> void:
	var card := Real.instance("EBP04-012")
	var rank3 := Cards.monster(3, 15000, [CardEnums.CardTrait.BIOLLANTE], "BIO-R3")
	var state := States.make_state({"p0": {
		"current_monster": Cards.monster(2, 9000, [CardEnums.CardTrait.BIOLLANTE], "BIO-R2"),
		"monster_deck": [rank3],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_cards": [[rank3]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	var paid: bool = await handler.apply_play_cost(0, card, -1)

	assert_bool(paid).is_true()
	assert_int(state.players[0].monster_deck.size()).is_equal(0)
	assert_str(str(state.players[0].monster_stack.back().get("id"))).is_equal("BIO-R3")


func test_ebp04_012_enter_plays_tentacles_in_adjacent_zones() -> void:
	var card := Real.instance("EBP04-012")
	# Monster zone 4 (idx 3) → adjacent zones [2, 4, 6].
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 4}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2, 4, 6]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.count_zone_tokens_by_id("EBP02-T02")).is_equal(3)
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("EBP02-T02")
	# Rule 5.11.1.3: each token must go to a different zone.
	assert_bool(2 in input.calls[1]["valid"]).is_false()


# --- EBP04-013: enter with 5+ monsters discarded → mill 3, destroy + retreat ---


func test_ebp04_013_mills_3_then_destroys_matching_zones_and_retreats() -> void:
	var monster := Real.instance("EBP04-013")
	var state := States.make_state({
		"p0": {
			"current_monster": monster,
			"main_deck": [Cards.battle(2, 2000, "TOP-R2"), Cards.battle(5, 2000, "TOP-R5"),
				Cards.battle(2, 2000, "TOP-R2B")],
		},
		"p1": {
			"zone_cards": {1: Cards.battle(3, 3000, "OPP-Z2"), 4: Cards.battle(3, 3000, "OPP-Z5")},
			"monster_zone": 5,
		},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}  # destroy first, then retreat
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	var p1 := state.players[1]
	# Revealed ranks {2, 5} → opponent zones 2 and 5 (idx 1, 4) destroyed.
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(4)).is_false()
	# Opponent monster was in zone 5 (a revealed rank) → retreated 1 zone.
	assert_int(p1.monster_zone).is_equal(4)
	assert_int(state.players[0].main_deck.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(8)


func test_ebp04_013_silent_below_5_monsters_in_discard() -> void:
	var monster := Real.instance("EBP04-013")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"main_deck": [Cards.battle(2, 2000, "TOP")],
	}})
	for i in range(4):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_int(state.players[0].main_deck.size()).is_equal(1)


# --- EBP04-014: hand battle discarded + opp rage 0 → destroy rank<=4;
# --- opp counter start Awk6 → discard battle for counter prevention <=30k ---


func test_ebp04_014_hand_battle_discard_destroys_rank_4_at_opp_rage_0() -> void:
	var monster := Real.instance("EBP04-014")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {
			"zone_cards": {1: Cards.battle(4, 3000, "OPP-R4"), 2: Cards.battle(5, 3000, "OPP-R5")},
			"monster_zone": 8,
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 2000, "DISCARDED"))

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_str(str(state.players[1].get_zone_top_card(2).get("id"))).is_equal("OPP-R5")
	# Only the rank<=4 zone was targetable.
	assert_array(input.calls[0]["valid"]).contains_exactly([1])


func test_ebp04_014_no_destroy_with_opp_rage_or_strategy_discard() -> void:
	# Opponent has rage: silent.
	var monster := Real.instance("EBP04-014")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {1: Cards.battle(2, 3000, "OPP")}, "rage": 1, "monster_zone": 8},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 2000, "D"))
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Strategy card discarded: TRIGGER_FILTERS card_type gate blocks it.
	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.strategy(2, "D-STR"))
	assert_int(input.count_calls("select_zone")).is_equal(0)


func test_ebp04_014_counter_prevention_after_discarding_battle_at_awakening_6() -> void:
	var monster := Real.instance("EBP04-014")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"current_monster": monster, "monster_zone": 6,
			"zone_cards": {1: Cards.battle(2, 2000, "Z1"), 2: Cards.battle(2, 2000, "Z2")},
			"hand": [Cards.battle(3, 3000, "H-BTL"), Cards.strategy(2, "H-STR")],
		},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(handler.is_counter_prevented(0, 30000)).is_true()
	assert_bool(handler.is_counter_prevented(0, 30001)).is_false()
	# Only battle cards were offered as the cost.
	assert_array(input.calls[0]["valid"]).contains_exactly([0])

	# End phase (opponent's turn) resets the prevention window.
	await handler.trigger_phase_end(CardEnums.GamePhase.END)
	assert_bool(handler.is_counter_prevented(0, 30000)).is_false()


func test_ebp04_014_no_prevention_prompt_below_awakening_6() -> void:
	var monster := Real.instance("EBP04-014")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"current_monster": monster, "monster_zone": 5,
			"zone_cards": {1: Cards.battle(2, 2000, "Z1"), 2: Cards.battle(2, 2000, "Z2")},
			"hand": [Cards.battle(3, 3000, "H-BTL")],
		},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_hand_card")).is_equal(0)


# --- EBP04-018: zone>=opp zone → +10000 TL; enter w/ 5 monsters → destroy <=6 ---


func test_ebp04_018_threat_bonus_when_at_or_past_opponent_zone() -> void:
	var monster := Real.instance("EBP04-018")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4}, "p1": {"monster_zone": 4}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_threat_level_modifier(0)).is_equal(10000)

	state.players[1].monster_zone = 5
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)


func test_ebp04_018_enter_destroys_rank_6_with_5_monsters_discarded() -> void:
	var monster := Real.instance("EBP04-018")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {
			"zone_cards": {2: Cards.battle(6, 3000, "OPP-R6"), 4: Cards.battle(7, 3000, "OPP-R7")},
			"monster_zone": 8,
		},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_bool(state.players[1].zone_has_cards(2)).is_false()
	assert_bool(state.players[1].zone_has_cards(4)).is_true()
	assert_array(input.calls[0]["valid"]).contains_exactly([2])


func test_ebp04_018_enter_silent_below_5_monsters_discarded() -> void:
	var monster := Real.instance("EBP04-018")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: Cards.battle(2, 3000, "OPP")}, "monster_zone": 8},
	})
	for i in range(4):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP04-022: countered → mill 5, destroy CP<=6000 in zones 1-5 per green ---


func test_ebp04_022_countered_mills_5_and_destroys_per_green_revealed() -> void:
	var monster := Real.instance("EBP04-022")
	var state := States.make_state({
		"p0": {
			"current_monster": monster,
			"main_deck": [
				_green_battle(2, 2000, "G1"), Cards.battle(2, 2000, "R1"),
				_green_battle(3, 2000, "G2"), Cards.strategy(2, "S1"),
				Cards.battle(2, 2000, "R2"),
			],
		},
		"p1": {
			"zone_cards": {
				1: Cards.battle(3, 3000, "OPP-LOW"),
				2: Cards.battle(3, 8000, "OPP-HIGH"),
				5: Cards.battle(3, 3000, "OPP-Z6"),
			},
			"monster_zone": 8,
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_counter_success(1, 0)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(2).get("id"))).is_equal("OPP-HIGH")  # CP > 6000
	assert_str(str(p1.get_zone_top_card(5).get("id"))).is_equal("OPP-Z6")    # zone 6
	assert_int(state.players[0].main_deck.size()).is_equal(0)
	# Only the low-CP zones-1-5 target was offered.
	assert_array(_calls(input, "select_zone")[0]["valid"]).contains_exactly([1])


func test_ebp04_022_no_destroy_when_no_green_revealed() -> void:
	var monster := Real.instance("EBP04-022")
	var state := States.make_state({
		"p0": {
			"current_monster": monster,
			"main_deck": [Cards.battle(2, 2000, "R1"), Cards.battle(2, 2000, "R2")],
		},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}, "monster_zone": 8},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_counter_success(1, 0)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(0)  # still milled
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP04-024: +1000 TL/green discard; enter w/ 10 green → destroy budget 7 ---


func test_ebp04_024_threat_scales_with_green_battle_discards() -> void:
	var monster := Real.instance("EBP04-024")
	var state := States.make_state({"p0": {"current_monster": monster}})
	for i in range(4):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "RED"))  # not green
	var s := _session(state)
	assert_int(s["effect_handler"].get_threat_level_modifier(0)).is_equal(4000)


func test_ebp04_024_enter_destroys_within_total_rank_budget_7() -> void:
	var monster := Real.instance("EBP04-024")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {
			"zone_cards": {
				0: Cards.battle(4, 3000, "OPP-R4"),
				1: Cards.battle(3, 3000, "OPP-R3"),
				2: Cards.battle(5, 3000, "OPP-R5"),
			},
			"monster_zone": 8,
		},
	})
	for i in range(10):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0, 1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(2).get("id"))).is_equal("OPP-R5")
	# After spending 4, only ranks <= 3 remain eligible (the rank 5 is out).
	assert_array(input.calls[1]["valid"]).contains_exactly([1])


func test_ebp04_024_enter_silent_below_10_green_discards() -> void:
	var monster := Real.instance("EBP04-024")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {0: Cards.battle(2, 3000, "OPP")}, "monster_zone": 8},
	})
	for i in range(9):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP04-025: enter destroys 1 opp strategy; invading w/ 10 green → opp to 3 ---


func test_ebp04_025_enter_destroys_chosen_opponent_strategy() -> void:
	var monster := Real.instance("EBP04-025")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"strategy_zones": [Cards.strategy(2, "OPP-S1"), Cards.strategy(3, "OPP-S2")]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_strategy": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_bool(state.players[1].strategy_zones[1].is_empty()).is_true()
	assert_str(str(state.players[1].strategy_zones[0].get("id"))).is_equal("OPP-S1")
	assert_str(str(state.players[1].discard_pile[0].get("id"))).is_equal("OPP-S2")


func test_ebp04_025_enter_silent_without_opponent_strategies() -> void:
	var monster := Real.instance("EBP04-025")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("select_strategy")).is_equal(0)


func test_ebp04_025_invading_discards_opponent_to_3_with_10_green() -> void:
	var monster := Real.instance("EBP04-025")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1), Cards.battle(1), Cards.battle(1)]},
	})
	for i in range(10):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var s := _session(state)

	await s["effect_handler"].trigger_when_invading(0, 4, 5)
	assert_int(state.players[1].hand.size()).is_equal(3)

	# Below 10 green: silent.
	var monster2 := Real.instance("EBP04-025", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": monster2, "monster_zone": 4},
		"p1": {"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1), Cards.battle(1), Cards.battle(1)]},
	})
	for i in range(9):
		state2.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_when_invading(0, 4, 5)
	assert_int(state2.players[1].hand.size()).is_equal(5)


# --- EBP04-026: invading plays 3 Crystals; Awk6 + 3 crystals → +10000 CP ---


func test_ebp04_026_invading_plays_3_crystals_and_boosts_cp_at_awakening_6() -> void:
	var monster := Real.instance("EBP04-026")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 6}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0, 1, 2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# No crystals yet: no CP bonus even at Awakening 6.
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)

	await handler.trigger_when_invading(0, 5, 6)

	var p0 := state.players[0]
	assert_int(p0.count_zone_tokens_by_id("EBP02-T03")).is_equal(3)
	assert_int(handler.get_counter_power_modifier(0)).is_equal(10000)

	# Below Awakening 6 the bonus turns off.
	p0.monster_zone = 5
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)

	# Back at 6 but only 2 crystals: off again.
	p0.monster_zone = 6
	p0.clear_zone(0)
	assert_int(handler.get_counter_power_modifier(0)).is_equal(0)


# --- EBP04-027: cannot advance/invade; main start → discard Step 2 to counter it ---


func test_ebp04_027_blocks_own_advance_and_invasion() -> void:
	var monster := Real.instance("EBP04-027")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.is_monster_advance_blocked(0)).is_true()
	assert_bool(handler.is_own_invasion_blocked(0)).is_true()


func test_ebp04_027_own_main_start_discard_step2_counters_itself() -> void:
	var monster := Real.instance("EBP04-027")
	var rankup := Cards.monster(2, 13000, [CardEnums.CardTrait.GIGAN], "GIGAN-R2")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"hand": [Cards.battle(2, 2000, "STEP2", [], 2)],
		"monster_deck": [rankup],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "choose_rankup": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.current_monster.get("id"))).is_equal("GIGAN-R2")
	assert_int(p0.monster_stack.size()).is_equal(1)
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(1)


func test_ebp04_027_opponent_pays_on_their_turn_and_may_decline() -> void:
	var monster := Real.instance("EBP04-027")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster},
		"p1": {"hand": [Cards.battle(2, 2000, "OPP-STEP2", [], 2)]},
	})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)

	# The opponent (player 1) was the one prompted; declining changes nothing.
	assert_int(input.calls[0]["player_id"]).is_equal(1)
	assert_str(str(state.players[0].current_monster.get("id"))).is_equal(str(monster.get("id")))


func test_ebp04_027_no_prompt_without_step2_card_in_hand() -> void:
	var monster := Real.instance("EBP04-027")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"hand": [Cards.battle(2, 2000, "STEP1", [], 1)],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)


# --- EBP04-028: opp turn → opp hand strategies +3 rank; deck-play → discard 1 ---


func test_ebp04_028_raises_opponent_hand_strategy_ranks_on_their_turn() -> void:
	var monster := Real.instance("EBP04-028")
	var strat := Cards.strategy(2, "OPP-HAND-STRAT")
	var state := States.make_state({"current_player_id": 1, "p0": {"current_monster": monster}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	# Opponent's (player 1's) hand strategy gains +3 on their turn.
	assert_int(handler.get_strategy_hand_rank_modifier(1, strat)).is_equal(3)
	# The owner's own hand is untouched.
	assert_int(handler.get_strategy_hand_rank_modifier(0, strat)).is_equal(0)

	# On the owner's turn the modifier is off.
	state.current_player_id = 0
	assert_int(handler.get_strategy_hand_rank_modifier(1, strat)).is_equal(0)


func test_ebp04_028_opponent_deck_play_costs_them_a_card() -> void:
	var monster := Real.instance("EBP04-028")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster},
		"p1": {"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1)]},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_battle_card_played(1, Cards.battle(3, 3000, "PLAYED"), 2, true)
	assert_int(state.players[1].hand.size()).is_equal(2)

	# Played from hand (not deck): filter blocks it.
	await handler.trigger_battle_card_played(1, Cards.battle(3, 3000, "PLAYED2"), 3, false)
	assert_int(state.players[1].hand.size()).is_equal(2)


# --- EBP04-029: blocks opp Step-1 invade cost; enter recovers Gigan monster ---


func test_ebp04_029_blocks_opponent_invade1_cost_only() -> void:
	var monster := Real.instance("EBP04-029")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	# Player 1 (the opponent of the card's owner) is blocked; the owner is not.
	assert_bool(handler.is_invade1_cost_blocked(1)).is_true()
	assert_bool(handler.is_invade1_cost_blocked(0)).is_false()


func test_ebp04_029_enter_recovers_gigan_monster_when_opp_in_zones_1_5() -> void:
	var monster := Real.instance("EBP04-029")
	var gigan := Cards.monster(2, 13000, [CardEnums.CardTrait.GIGAN], "DISC-GIGAN")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"monster_zone": 4},
	})
	state.players[0].discard_pile.append_array([gigan, Cards.monster(2, 9000, [], "DISC-OTHER")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DISC-GIGAN"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("DISC-GIGAN")
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp04_029_enter_silent_when_opp_monster_past_zone_5() -> void:
	var monster := Real.instance("EBP04-029")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"monster_zone": 6},
	})
	state.players[0].discard_pile.append(Cards.monster(2, 13000, [CardEnums.CardTrait.GIGAN], "DISC-GIGAN"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP04-030: opp turn end-phase draw block; enter destroys in zones 1-5 ---


func test_ebp04_030_blocks_opponent_end_phase_draw_on_their_turn() -> void:
	var monster := Real.instance("EBP04-030")
	var state := States.make_state({"current_player_id": 1, "p0": {"current_monster": monster}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.is_opponent_end_phase_draw_blocked(1)).is_true()

	# On the owner's own turn the block is off.
	state.current_player_id = 0
	assert_bool(handler.is_opponent_end_phase_draw_blocked(1)).is_false()


func test_ebp04_030_enter_destroys_opponent_card_in_zones_1_5() -> void:
	var monster := Real.instance("EBP04-030")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {
			"zone_cards": {1: Cards.battle(3, 3000, "OPP-Z2"), 6: Cards.battle(3, 3000, "OPP-Z7")},
			"monster_zone": 8,
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(6)).is_true()
	assert_array(input.calls[0]["valid"]).contains_exactly([1])


func test_ebp04_030_enter_silent_with_targets_only_in_zones_6_8() -> void:
	var monster := Real.instance("EBP04-030")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {6: Cards.battle(3, 3000, "OPP-Z7")}, "monster_zone": 8},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP04-033: playable on Monster X; enter 3 discard colors → opp rage -1 ---


func test_ebp04_033_playable_on_top_of_monster_x() -> void:
	var card := Real.instance("EBP04-033")
	var state := States.make_state({"p0": {
		"current_monster": Cards.monster(2, 9000, [CardEnums.CardTrait.MONSTER_X], "MX"),
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.can_monster_be_played_from_hand(0, card)).is_true()

	state.players[0].current_monster = Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "GOJI")
	assert_bool(handler.can_monster_be_played_from_hand(0, card)).is_false()


func test_ebp04_033_enter_reduces_rage_with_3_discard_colors() -> void:
	var monster := Real.instance("EBP04-033")
	var state := States.make_state({"p0": {"current_monster": monster}, "p1": {"rage": 2}})
	state.players[0].discard_pile.append_array([
		_colored_battle(2, 2000, "C-R", CardEnums.CardColor.RED),
		_colored_battle(2, 2000, "C-B", CardEnums.CardColor.BLUE),
		_colored_battle(2, 2000, "C-G", CardEnums.CardColor.GREEN),
	])
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(state.players[1].rage).is_equal(1)

	# Only 2 colors: silent.
	var monster2 := Real.instance("EBP04-033", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2}, "p1": {"rage": 2}})
	state2.players[0].discard_pile.append_array([
		_colored_battle(2, 2000, "C-R", CardEnums.CardColor.RED),
		_colored_battle(2, 2000, "C-B", CardEnums.CardColor.BLUE),
	])
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, monster2)
	assert_int(state2.players[1].rage).is_equal(2)


# --- EBP04-039: opp turn, non-red ally destroyed → move adjacent to monster ---


func test_ebp04_039_moves_adjacent_to_monster_when_non_red_ally_destroyed() -> void:
	var card := Real.instance("EBP04-039")
	var blue := _colored_battle(3, 3000, "ALLY-BLUE", CardEnums.CardColor.BLUE)
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {1: card, 4: blue}, "monster_zone": 4},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [4])

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(1)).is_false()
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))
	# Offered destinations: zones adjacent to the monster (zone 4 → idx 2, 4, 6).
	assert_array(input.calls[0]["valid"]).contains_exactly([2, 4, 6])


func test_ebp04_039_stays_on_own_turn_or_for_red_destruction() -> void:
	# Own turn: silent.
	var card := Real.instance("EBP04-039")
	var blue := _colored_battle(3, 3000, "ALLY-BLUE", CardEnums.CardColor.BLUE)
	var state := States.make_state({"p0": {"zone_cards": {1: card, 4: blue}, "monster_zone": 4}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.destroy_zones(state.players[0], [4])
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Red battle card destroyed: silent.
	var card2 := Real.instance("EBP04-039", 1)
	var state2 := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {1: card2, 4: Cards.battle(3, 3000, "ALLY-RED")}, "monster_zone": 4},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.destroy_zones(state2.players[0], [4])
	assert_int(input2.count_calls("select_zone")).is_equal(0)


# --- EBP04-040: Awk6 enter w/ Rodan + King Caesar battle cards → +3 rage ---


func test_ebp04_040_enter_gains_3_rage_with_rodan_and_king_caesar_at_awk6() -> void:
	var card := Real.instance("EBP04-040")
	var state := States.make_state({"p0": {
		"monster_zone": 6,
		"zone_cards": {
			1: Cards.battle(3, 3000, "RDN", [CardEnums.CardTrait.RODAN]),
			2: Cards.battle(3, 3000, "KC", [CardEnums.CardTrait.KING_CAESAR]),
			3: card,
		},
	}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].rage).is_equal(3)


func test_ebp04_040_enter_silent_below_awk6_or_missing_partner() -> void:
	var card := Real.instance("EBP04-040")
	var state := States.make_state({"p0": {
		"monster_zone": 5,
		"zone_cards": {
			1: Cards.battle(3, 3000, "RDN", [CardEnums.CardTrait.RODAN]),
			2: Cards.battle(3, 3000, "KC", [CardEnums.CardTrait.KING_CAESAR]),
			3: card,
		},
	}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].rage).is_equal(0)

	var card2 := Real.instance("EBP04-040", 1)
	var state2 := States.make_state({"p0": {
		"monster_zone": 6,
		"zone_cards": {1: Cards.battle(3, 3000, "RDN", [CardEnums.CardTrait.RODAN]), 3: card2},
	}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP04-041: own counter start in zone 8 re-triggers monster enter; Awk6 CP ---


func test_ebp04_041_zone8_counter_start_retriggers_monster_enter() -> void:
	var card := Real.instance("EBP04-041")
	# Monster: EBP04-004 — its enter grants +2 rage with a rank 1 strategy in play.
	var monster := Real.instance("EBP04-004")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"zone_cards": {7: card},
		"strategy_zones": [Cards.strategy(1, "S-R1")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(2)


func test_ebp04_041_silent_outside_zone_8_and_cp_bonus_at_awk6() -> void:
	var card := Real.instance("EBP04-041")
	var monster := Real.instance("EBP04-004", 1)
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"zone_cards": {4: card},
		"strategy_zones": [Cards.strategy(1, "S-R1")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].rage).is_equal(0)

	# CP: +3000 only at Awakening 6.
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(4000)
	state.players[0].monster_zone = 6
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(7000)


# --- EBP04-042: enter w/ 3 rank1 strategies discarded → opp rage -1 ---


func test_ebp04_042_enter_reduces_rage_with_3_rank1_strategies_discarded() -> void:
	var card := Real.instance("EBP04-042")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"rage": 2}})
	for i in range(3):
		state.players[0].discard_pile.append(Cards.strategy(1, "DS%d" % i))
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)

	# Only 2 in discard: silent.
	var card2 := Real.instance("EBP04-042", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}, "p1": {"rage": 2}})
	state2.players[0].discard_pile.append_array([Cards.strategy(1, "DS0"), Cards.strategy(1, "DS1")])
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(2)


# --- EBP04-043: counter start → tuck Step-2 strategy under; +10000 CP w/ card ---


func test_ebp04_043_counter_start_places_step2_strategy_under_for_cp() -> void:
	var card := Real.instance("EBP04-043")
	var base: int = card.get("counter_power", 0)
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"strategy_zones": [Cards.strategy(2, "S-I2", 2)],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_strategy": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base)

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_bool(p0.strategy_zones[0].is_empty()).is_true()
	assert_int(handler.get_cards_under_top(p0, 2).size()).is_equal(1)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base + 10000)


func test_ebp04_043_declining_or_no_step2_strategy_does_nothing() -> void:
	# Decline the 'may': strategy stays put.
	var card := Real.instance("EBP04-043")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"strategy_zones": [Cards.strategy(2, "S-I2", 2)],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_false()
	assert_int(input.count_calls("select_strategy")).is_equal(0)

	# No Step-2 strategy in play: no prompt at all.
	var card2 := Real.instance("EBP04-043", 1)
	var state2 := States.make_state({"p0": {
		"zone_cards": {2: card2},
		"strategy_zones": [Cards.strategy(2, "S-I0", 0)],
	}})
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input2.count_calls("choose_option")).is_equal(0)


# --- EBP04-045: discard non-blue battle to play at rank -2 ---


func test_ebp04_045_play_rank_minus_2_only_with_non_blue_battle_in_hand() -> void:
	var card := Real.instance("EBP04-045")
	var state := States.make_state({"p0": {"hand": [card, Cards.battle(2, 2000, "RED")]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-2)

	# Only blue battle cards (itself included) in hand: no reduction.
	state.players[0].hand.remove_at(1)
	state.players[0].hand.append(_colored_battle(2, 2000, "BLUE", CardEnums.CardColor.BLUE))
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_ebp04_045_play_cost_discards_non_blue_battle() -> void:
	var card := Real.instance("EBP04-045")
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(2, 2000, "RED-COST")]},
		"p1": {"monster_zone": 1},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	var ok: bool = await handler.apply_play_cost(0, card, 2)

	assert_bool(ok).is_true()
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("RED-COST")


func test_ebp04_045_skipping_cost_falls_back_to_base_rank_fit() -> void:
	# Opponent at zone 1: base rank 3 doesn't fit → play fails when skipping.
	var card := Real.instance("EBP04-045")
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(2, 2000, "RED-COST")]},
		"p1": {"monster_zone": 1},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(await handler.apply_play_cost(0, card, 2)).is_false()
	assert_int(state.players[0].hand.size()).is_equal(1)

	# Opponent at zone 3: base rank already fits → skipping is fine.
	var card2 := Real.instance("EBP04-045", 1)
	var state2 := States.make_state({
		"p0": {"hand": [Cards.battle(2, 2000, "RED-COST")]},
		"p1": {"monster_zone": 3},
	})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_bool(await handler2.apply_play_cost(0, card2, 2)).is_true()


# --- EBP04-046: discarded by opp effect → may play; Awk6 +3000 CP ---


func test_ebp04_046_plays_itself_when_discarded_by_opponent_effect() -> void:
	var card := Real.instance("EBP04-046")
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	# Simulate an opponent effect causing the discard.
	handler.exec.active_player_id = 1
	handler.exec.active_card = Cards.strategy(2, "OPP-FX")

	await handler.trigger_discard_from_hand(0, card)

	assert_str(str(state.players[0].get_zone_top_card(4).get("id"))).is_equal(str(card.get("id")))
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_ebp04_046_silent_when_discarded_by_own_effect_and_awk6_cp() -> void:
	var card := Real.instance("EBP04-046")
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.active_player_id = 0
	handler.exec.active_card = Cards.strategy(2, "OWN-FX")

	await handler.trigger_discard_from_hand(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)

	# Awakening 6 CP bonus.
	var card2 := Real.instance("EBP04-046", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_int(handler2.get_effective_zone_cp(0, 2)).is_equal(2000)
	state2.players[0].monster_zone = 6
	assert_int(handler2.get_effective_zone_cp(0, 2)).is_equal(5000)


# --- EBP04-047: CP = 3000 x distinct colors of OTHER battle cards; Evolution 8 ---


func test_ebp04_047_cp_scales_with_distinct_colors_of_other_battle_cards() -> void:
	var card := Real.instance("EBP04-047")
	var state := States.make_state({"p0": {"zone_cards": {
		2: card,
		1: _colored_battle(2, 2000, "C-R", CardEnums.CardColor.RED),
		3: _colored_battle(2, 2000, "C-G", CardEnums.CardColor.GREEN),
		4: _colored_battle(2, 2000, "C-W", CardEnums.CardColor.WHITE),
	}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(9000)

	# Alone on the board: X = 0.
	var card2 := Real.instance("EBP04-047", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_int(handler2.get_effective_zone_cp(0, 2)).is_equal(0)


func test_ebp04_047_evolves_into_kaizer_ghidorah_at_main_start() -> void:
	var card := Real.instance("EBP04-047")
	var kg := Cards.battle(8, 9000, "KG", [CardEnums.CardTrait.KAISER_GHIDORAH])
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(2, 2000, "D1"), kg],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "KG"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("KG")
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)


func test_ebp04_047_no_evolution_on_opponent_turn() -> void:
	var card := Real.instance("EBP04-047")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"zone_cards": {2: card},
			"main_deck": [Cards.battle(8, 9000, "KG", [CardEnums.CardTrait.KAISER_GHIDORAH])],
		},
	})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP04-049: own counter start w/ rank8+ battle → mill 1, branch on color ---


func test_ebp04_049_non_blue_reveal_reduces_opponent_rage_2() -> void:
	var card := Real.instance("EBP04-049")
	var state := States.make_state({
		"p0": {
			"zone_cards": {4: card, 6: Cards.battle(8, 8000, "R8")},
			"main_deck": [Cards.battle(2, 2000, "TOP-RED")],
		},
		"p1": {"rage": 3},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].main_deck.size()).is_equal(0)


func test_ebp04_049_blue_reveal_destroys_own_rank8_card() -> void:
	var card := Real.instance("EBP04-049")
	var state := States.make_state({"p0": {
		"zone_cards": {4: card, 6: Cards.battle(8, 8000, "R8")},
		"main_deck": [_colored_battle(2, 2000, "TOP-BLUE", CardEnums.CardColor.BLUE)],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [6]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[0].zone_has_cards(6)).is_false()
	assert_array(_calls(input, "select_zone")[0]["valid"]).contains_exactly([6])


func test_ebp04_049_silent_without_rank8_battle_card() -> void:
	var card := Real.instance("EBP04-049")
	var state := States.make_state({"p0": {
		"zone_cards": {4: card, 6: Cards.battle(7, 8000, "R7")},
		"main_deck": [Cards.battle(2, 2000, "TOP")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].main_deck.size()).is_equal(1)
