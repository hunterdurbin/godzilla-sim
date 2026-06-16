extends GdUnitTestSuite

## Tier C bespoke tests for EBP03 cards 001-041 — one-of-a-kind effects driven
## through the real trigger-dispatch seam (trigger_* / destroy_zones /
## aggregation queries). See classification.md for the bespoke list; cards
## 042-080 live in test_ebp03_bespoke_b.gd.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


# --- EBP03-001: Godzilla(2001) R1 — end phase discard r5+ → advance; Awk6 +5000 TL ---


func test_ebp03_001_end_phase_discard_advances_monster() -> void:
	var card := Real.instance("EBP03-001")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 4,
		"hand": [Cards.battle(4, 3000, "R4"), Cards.battle(5, 3000, "R5")],
	}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(state.players[0].monster_zone).is_equal(5)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	# Only the rank-5 battle card was offered as a discard.
	assert_bool(0 in input.calls[0]["valid"]).is_false()
	assert_bool(1 in input.calls[0]["valid"]).is_true()


func test_ebp03_001_silent_below_awakening4_and_no_advance_at_zone8() -> void:
	# Below Awakening4: no prompt at all.
	var card := Real.instance("EBP03-001")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 3,
		"hand": [Cards.battle(5, 3000, "R5")],
	}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(state.players[0].monster_zone).is_equal(3)

	# At zone 8 the discard still resolves but the monster cannot advance.
	var card2 := Real.instance("EBP03-001", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": card2, "monster_zone": 8,
		"hand": [Cards.battle(5, 3000, "R5B")],
	}})
	state2.current_phase = CardEnums.GamePhase.END
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [0]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state2.players[0].monster_zone).is_equal(8)
	assert_int(state2.players[0].discard_pile.size()).is_equal(1)


func test_ebp03_001_threat_modifier_only_with_awakening6() -> void:
	var card := Real.instance("EBP03-001")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 5}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)
	state.players[0].monster_zone = 6
	assert_int(handler.get_threat_level_modifier(0)).is_equal(5000)


# --- EBP03-002: Godzilla(2001) R2 — counter-start discards for rage (+1/+2) ---


func test_ebp03_002_opponent_turn_awakening4_gains_1_rage() -> void:
	var card := Real.instance("EBP03-002")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "monster_zone": 4, "hand": [Cards.battle(5, 3000, "R5")]},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_ebp03_002_own_turn_awakening8_gains_2_rage() -> void:
	var card := Real.instance("EBP03-002")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 8, "hand": [Cards.battle(5, 3000, "R5")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(2)


func test_ebp03_002_own_turn_below_awakening8_is_silent() -> void:
	var card := Real.instance("EBP03-002")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 4, "hand": [Cards.battle(5, 3000, "R5")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(state.players[0].rage).is_equal(0)


# --- EBP03-003: Godzilla(2001) R3 — Burst2; Awk8 counter-start +2 rage + destroy ≤6 ---


func test_ebp03_003_awakening8_discard_gains_rage_and_destroys_rank6_or_lower() -> void:
	var card := Real.instance("EBP03-003")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 8, "hand": [Cards.battle(5, 3000, "R5")]},
		"p1": {"zone_cards": {1: Cards.battle(6, 4000, "OPP-R6"), 3: Cards.battle(7, 4000, "OPP-R7")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(2)
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_str(str(state.players[1].get_zone_top_card(3).get("id"))).is_equal("OPP-R7")
	assert_int(handler.queries.get_burst_rank(card)).is_equal(2)


func test_ebp03_003_silent_below_awakening8() -> void:
	var card := Real.instance("EBP03-003")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 7, "hand": [Cards.battle(5, 3000, "R5")]},
		"p1": {"zone_cards": {1: Cards.battle(6, 4000, "OPP-R6")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-004: Godzilla(2001) R4 — rage-reduction immunity + invasion mill replacement ---


func test_ebp03_004_prevents_rage_reduction_on_opponent_turn_awakening4() -> void:
	var card := Real.instance("EBP03-004")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "monster_zone": 4, "rage": 2},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_bool(handler.is_rage_reduction_prevented(0)).is_true()
	var reduced: int = await handler.reduce_rage(0, 1)
	assert_int(reduced).is_equal(0)
	assert_int(state.players[0].rage).is_equal(2)


func test_ebp03_004_rage_reduction_allowed_on_own_turn_or_below_awakening4() -> void:
	# Own turn: not protected.
	var card := Real.instance("EBP03-004")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 4, "rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.is_rage_reduction_prevented(0)).is_false()
	var reduced: int = await handler.reduce_rage(0, 1)
	assert_int(reduced).is_equal(1)
	assert_int(state.players[0].rage).is_equal(1)

	# Opponent's turn but below Awakening4: not protected.
	var card2 := Real.instance("EBP03-004", 1)
	var state2 := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card2, "monster_zone": 3, "rage": 2},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_bool(handler2.is_rage_reduction_prevented(0)).is_false()


func test_ebp03_004_can_replace_invasion_cost() -> void:
	var card := Real.instance("EBP03-004")
	var state := States.make_state({"p0": {"current_monster": card}})
	var s := _session(state)
	assert_bool(s["effect_handler"].can_replace_invasion_cost(0)).is_true()
	# A plain fixture monster offers no replacement.
	var state2 := States.make_state({})
	var s2 := _session(state2)
	assert_bool(s2["effect_handler"].can_replace_invasion_cost(0)).is_false()


# --- EBP03-005: Godzilla(2001) R4 — Burst3; Awk8 counter-start +3 rage + destroy ≤7 ---


func test_ebp03_005_awakening8_discard_gains_3_rage_and_destroys_rank7_or_lower() -> void:
	var card := Real.instance("EBP03-005")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 8, "hand": [Cards.battle(5, 3000, "R5")]},
		"p1": {"zone_cards": {1: Cards.battle(7, 4000, "OPP-R7"), 3: Cards.battle(8, 4000, "OPP-R8")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(3)
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_str(str(state.players[1].get_zone_top_card(3).get("id"))).is_equal("OPP-R8")
	assert_int(handler.queries.get_burst_rank(card)).is_equal(3)


func test_ebp03_005_skipping_the_discard_does_nothing() -> void:
	var card := Real.instance("EBP03-005")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 8, "hand": [Cards.battle(5, 3000, "R5")]},
		"p1": {"zone_cards": {1: Cards.battle(7, 4000, "OPP-R7")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-008: MFS-3 R3 — enter (blue gate) / opp counter start (red gate, column) ---


func test_ebp03_008_enter_destroys_rank5_or_lower_with_blue_battle_in_zones() -> void:
	var card := Real.instance("EBP03-008")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: blue}},
		"p1": {"zone_cards": {2: Cards.battle(5, 3000, "OPP-R5"), 4: Cards.battle(6, 3000, "OPP-R6")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(2)).is_false()
	# Rank-6 card was never offered.
	assert_bool(4 in input.calls[0]["valid"]).is_false()


func test_ebp03_008_enter_silent_without_blue_battle() -> void:
	var card := Real.instance("EBP03-008")
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: Cards.battle(2, 2000, "RED")}},
		"p1": {"zone_cards": {2: Cards.battle(5, 3000, "OPP-R5")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(2)).is_true()


func test_ebp03_008_opponent_counter_start_destroys_in_own_monster_column() -> void:
	# Monster at zone 5 (idx 4) → opponent column zone idx 0; red battle gate.
	var card := Real.instance("EBP03-008")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "monster_zone": 5, "zone_cards": {1: Cards.battle(2, 2000, "RED")}},
		"p1": {"monster_zone": 3, "zone_cards": {0: Cards.battle(5, 3000, "OPP-COL")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[1].zone_has_cards(0)).is_false()


func test_ebp03_008_opponent_counter_start_silent_without_red_battle() -> void:
	var card := Real.instance("EBP03-008")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "monster_zone": 5, "zone_cards": {1: blue}},
		"p1": {"monster_zone": 3, "zone_cards": {0: Cards.battle(5, 3000, "OPP-COL")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(0)).is_true()


# --- EBP03-009: MFS-3 R4 — enter destroys chosen column zone + adjacent (rank ≤6) ---


func test_ebp03_009_enter_destroys_chosen_zone_and_adjacent_up_to_rank6() -> void:
	# Monster zone 3 (idx 2) → opponent column zones idx [2, 7]; choose idx 2,
	# affected = [2] + adjacent [1, 3, 7].
	var card := Real.instance("EBP03-009")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 3},
		"p1": {"zone_cards": {
			2: Cards.battle(4, 3000, "OPP-A"),
			1: Cards.battle(4, 3000, "OPP-B"),
			3: Cards.battle(7, 3000, "OPP-R7"),
			7: Cards.battle(4, 3000, "OPP-C"),
			5: Cards.battle(4, 3000, "OPP-SAFE"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(7)).is_false()
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP-R7")
	assert_str(str(p1.get_zone_top_card(5).get("id"))).is_equal("OPP-SAFE")
	# Offered zones were exactly the cross-board column of the monster.
	assert_that(input.calls[0]["valid"]).is_equal([2, 7])


func test_ebp03_009_destroys_nothing_when_all_affected_cards_above_rank6() -> void:
	var card := Real.instance("EBP03-009")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 3},
		"p1": {"zone_cards": {2: Cards.battle(7, 3000, "OPP-R7"), 1: Cards.battle(8, 3000, "OPP-R8")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(2)).is_true()
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-010: MFS-3 R3 — enter: 2+ battle cards → opp discards to 4; battle → +1 rage ---


func test_ebp03_010_enter_forces_discard_to_4_and_gains_rage_for_battle() -> void:
	var card := Real.instance("EBP03-010")
	var opp_hand: Array = [
		Cards.battle(2, 2000, "OH-B1"), Cards.strategy(2, "OH-S1"), Cards.strategy(2, "OH-S2"),
		Cards.strategy(2, "OH-S3"), Cards.strategy(2, "OH-S4"), Cards.battle(2, 2000, "OH-B2"),
	]
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: Cards.battle(2), 2: Cards.battle(3)}},
		"p1": {"hand": opp_hand},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[0, 5]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(state.players[0].rage).is_equal(1)


func test_ebp03_010_no_rage_when_only_strategies_discarded() -> void:
	var card := Real.instance("EBP03-010")
	var opp_hand: Array = [
		Cards.battle(2, 2000, "OH-B1"), Cards.strategy(2, "OH-S1"), Cards.strategy(2, "OH-S2"),
		Cards.strategy(2, "OH-S3"), Cards.strategy(2, "OH-S4"),
	]
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: Cards.battle(2), 2: Cards.battle(3)}},
		"p1": {"hand": opp_hand},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[4]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_int(state.players[0].rage).is_equal(0)


func test_ebp03_010_silent_with_fewer_than_2_battle_cards() -> void:
	var card := Real.instance("EBP03-010")
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: Cards.battle(2)}},
		"p1": {"hand": [Cards.battle(2), Cards.battle(2, 2000, "B2"), Cards.battle(2, 2000, "B3"),
			Cards.battle(2, 2000, "B4"), Cards.battle(2, 2000, "B5")]},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("choose_hand_discards")).is_equal(0)
	assert_int(state.players[1].hand.size()).is_equal(5)


# --- EBP03-012: Godzilla(1993) R2 — enter: place blue ≤6 strategy from hand + activate ---


func test_ebp03_012_enter_places_blue_strategy_from_hand_into_strategy_zone() -> void:
	var card := Real.instance("EBP03-012")
	var strategy := Cards.strategy(2, "BLUE-STRAT")  # fixture strategies are blue
	var state := States.make_state({"p0": {
		"current_monster": card,
		"hand": [Cards.battle(2, 2000, "BTL"), strategy],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.strategy_zones[0].get("id"))).is_equal("BLUE-STRAT")
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_int(p0.hand.size()).is_equal(1)
	# Only the strategy was offered (battle filtered out).
	assert_that(input.calls[0]["valid"]).is_equal([1])


func test_ebp03_012_silent_with_2_strategies_in_play_and_skippable() -> void:
	# Two strategies already in play: no prompt.
	var card := Real.instance("EBP03-012")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"hand": [Cards.strategy(2, "BLUE-STRAT")],
		"strategy_zones": [Cards.strategy(1, "SA"), Cards.strategy(1, "SB")],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Skipping keeps the hand intact.
	var card2 := Real.instance("EBP03-012", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": card2, "hand": [Cards.strategy(2, "BLUE-STRAT2")],
	}})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[0].hand.size()).is_equal(1)
	assert_bool(state2.players[0].strategy_zones[0].is_empty()).is_true()


# --- EBP03-013: Godzilla(1995) R4 — 3 strategy zones; lose if none at opp counter ---


func test_ebp03_013_enter_expands_strategy_zones_to_3() -> void:
	var card := Real.instance("EBP03-013")
	var state := States.make_state({"p0": {"current_monster": card}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].strategy_zones.size()).is_equal(3)
	assert_bool(state.players[0].strategy_zones[2].is_empty()).is_true()
	assert_int(state.players[0].strategy_zone_stacks.size()).is_equal(3)


func test_ebp03_013_loses_game_at_opponent_counter_start_with_no_strategies() -> void:
	var card := Real.instance("EBP03-013")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	var winners: Array = []
	state.game_over.connect(func(winner_id: int, _reason: String) -> void: winners.append(winner_id))

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(winners.size()).is_equal(1)
	assert_int(winners[0]).is_equal(1)


func test_ebp03_013_survives_with_a_strategy_in_play() -> void:
	var card := Real.instance("EBP03-013")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "strategy_zones": [Cards.strategy(2, "S")]},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	var winners: Array = []
	state.game_over.connect(func(winner_id: int, _reason: String) -> void: winners.append(winner_id))

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(winners.size()).is_equal(0)


# --- EBP03-014: Godzilla(2002) R1 — end phase: discard battle → draw 1 ---


func test_ebp03_014_end_phase_discard_battle_draws_1() -> void:
	var card := Real.instance("EBP03-014")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"hand": [Cards.battle(2, 2000, "BTL")],
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("D1")
	assert_int(p0.discard_pile.size()).is_equal(1)


func test_ebp03_014_skip_or_no_battle_means_no_draw() -> void:
	# Skipped: no draw.
	var card := Real.instance("EBP03-014")
	var state := States.make_state({"p0": {
		"current_monster": card, "hand": [Cards.battle(2, 2000, "BTL")],
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].main_deck.size()).is_equal(1)

	# Only strategies in hand: no prompt at all.
	var card2 := Real.instance("EBP03-014", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": card2, "hand": [Cards.strategy(2, "S")],
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	state2.current_phase = CardEnums.GamePhase.END
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)


# --- EBP03-017: Godzilla(2003) R4 — battle discard → rage drain; enter discard → destroy ≤6 ---


func test_ebp03_017_battle_discard_reduces_opponent_rage_or_gains_own() -> void:
	# Opponent has rage: reduce it.
	var card := Real.instance("EBP03-017")
	var state := States.make_state({"p0": {"current_monster": card}, "p1": {"rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_hand_card_discarded(0, Cards.battle(3, 2000, "DISC"))
	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].rage).is_equal(0)

	# Opponent at 0: gain own rage instead.
	var card2 := Real.instance("EBP03-017", 1)
	var state2 := States.make_state({"p0": {"current_monster": card2}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_hand_card_discarded(0, Cards.battle(3, 2000, "DISC"))
	assert_int(state2.players[0].rage).is_equal(1)


func test_ebp03_017_strategy_discard_does_not_trigger() -> void:
	var card := Real.instance("EBP03-017")
	var state := States.make_state({"p0": {"current_monster": card}, "p1": {"rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_hand_card_discarded(0, Cards.strategy(3, "S"))

	assert_int(state.players[1].rage).is_equal(2)
	assert_int(state.players[0].rage).is_equal(0)


func test_ebp03_017_enter_discard_destroys_rank6_and_discard_trigger_chains() -> void:
	var card := Real.instance("EBP03-017")
	var state := States.make_state({
		"p0": {"current_monster": card, "hand": [Cards.battle(3, 2000, "COST")]},
		"p1": {"rage": 2, "zone_cards": {1: Cards.battle(6, 4000, "OPP-R6"), 3: Cards.battle(7, 4000, "OPP-R7")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "select_zone": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(3)).is_true()
	# The discard also fed the monster's own hand-discard trigger.
	assert_int(state.players[1].rage).is_equal(1)


func test_ebp03_017_enter_skip_keeps_everything() -> void:
	var card := Real.instance("EBP03-017")
	var state := States.make_state({
		"p0": {"current_monster": card, "hand": [Cards.battle(3, 2000, "COST")]},
		"p1": {"rage": 2, "zone_cards": {1: Cards.battle(6, 4000, "OPP-R6")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(state.players[1].rage).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(1)


# --- EBP03-023: Armor Mothra R4 — enter evolves Mothras; counter success + Base → retreat to 1 ---


func test_ebp03_023_enter_evolves_mothra_battle_cards() -> void:
	var monster := Real.instance("EBP03-023")
	var larva := Real.instance("EBP03-044")   # Evolution7 <Mothra>
	var imago := Real.instance("EBP03-045")   # rank 4 Mothra battle
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"zone_cards": {2: larva, 4: Cards.battle(3, 2000, "NO-EVO")},
		"main_deck": [Cards.battle(2, 2000, "FILLER"), imago],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": imago.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(imago.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# Search pool offered only the Mothra battle card of rank <= 7.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp03_023_counter_success_retreats_opponent_only_with_base() -> void:
	var monster := Real.instance("EBP03-023")
	var base := Cards.strategy(3, "BASE")
	base["is_base"] = true
	var state := States.make_state({
		"p0": {"current_monster": monster, "strategy_zones": [base]},
		"p1": {"monster_zone": 4},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_counter_success(0, 1)
	assert_int(state.players[1].monster_zone).is_equal(1)

	# No Base in play: no retreat.
	var monster2 := Real.instance("EBP03-023", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": monster2},
		"p1": {"monster_zone": 4},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_counter_success(0, 1)
	assert_int(state2.players[1].monster_zone).is_equal(4)


# --- EBP03-025: Mothra(imago)(2001) R2 — own-turn opp rank -1; enter: stack monster → advance opp to 5 ---


func test_ebp03_025_reduces_opponent_field_rank_by_1_on_own_turn() -> void:
	var monster := Real.instance("EBP03-025")
	var opp_card := Cards.battle(5, 3000, "OPP")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: opp_card}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(4)
	state.current_player_id = 1
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(5)


func test_ebp03_025_enter_stacks_discard_monster_and_advances_opponent_to_5() -> void:
	var monster := Real.instance("EBP03-025")
	var buried := Cards.monster(2, 9000, [CardEnums.CardTrait.MOTHRA], "DISC-MON")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"monster_zone": 2},
	})
	state.players[0].discard_pile.append(buried)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DISC-MON"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[0].monster_stack.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_int(state.players[1].monster_zone).is_equal(5)


func test_ebp03_025_enter_skip_leaves_opponent_in_place() -> void:
	var monster := Real.instance("EBP03-025")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"monster_zone": 2},
	})
	state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DISC-MON"))
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[0].monster_stack.size()).is_equal(0)
	assert_int(state.players[1].monster_zone).is_equal(2)


# --- EBP03-026: Mothra(imago)(2001) R3 — stack 3+ → opp rank -2; enter: stack 2 → opp -1 rage ---


func test_ebp03_026_field_rank_minus_2_needs_3_under_and_own_turn() -> void:
	var monster := Real.instance("EBP03-026")
	var opp_card := Cards.battle(5, 3000, "OPP")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: opp_card}},
	})
	var p0 := state.players[0]
	for i in range(3):
		p0.monster_stack.append(Cards.monster(1, 4000, [], "UNDER-%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(3)
	# Opponent's turn: inactive.
	state.current_player_id = 1
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(5)
	# Only 2 under: inactive.
	state.current_player_id = 0
	p0.monster_stack.pop_back()
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(5)


func test_ebp03_026_enter_buries_2_monsters_and_reduces_opponent_rage() -> void:
	var monster := Real.instance("EBP03-026")
	var m1 := Cards.monster(1, 4000, [], "DM1")
	var m2 := Cards.monster(2, 9000, [], "DM2")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"rage": 2},
	})
	state.players[0].discard_pile.append_array([m1, m2, Cards.battle(2, 2000, "BTL")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_cards": [[m1, m2]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	var p0 := state.players[0]
	assert_int(p0.monster_stack.size()).is_equal(2)
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_int(state.players[1].rage).is_equal(1)
	# Pool offered only the 2 monsters.
	assert_int(input.calls[0]["matching"].size()).is_equal(2)


func test_ebp03_026_enter_silent_with_fewer_than_2_monsters_in_discard() -> void:
	var monster := Real.instance("EBP03-026")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"rage": 2},
	})
	state.players[0].discard_pile.append(Cards.monster(1, 4000, [], "DM1"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(input.count_calls("select_cards")).is_equal(0)
	assert_int(state.players[1].rage).is_equal(2)


# --- EBP03-027: Ghidorah(2001) R3 — stack 3+ rank -2; invading w/ stack 5+ → opp discards to 4 ---


func test_ebp03_027_field_rank_minus_2_with_3_under_on_own_turn() -> void:
	var monster := Real.instance("EBP03-027")
	var opp_card := Cards.battle(5, 3000, "OPP")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: opp_card}},
	})
	for i in range(3):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(3)
	state.current_player_id = 1
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(5)


func test_ebp03_027_invading_with_5_under_forces_discard_to_4() -> void:
	var monster := Real.instance("EBP03-027")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {"hand": [Cards.battle(2), Cards.battle(2, 2000, "H2"), Cards.battle(2, 2000, "H3"),
			Cards.battle(2, 2000, "H4"), Cards.battle(2, 2000, "H5"), Cards.battle(2, 2000, "H6")]},
	})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(1)


func test_ebp03_027_invading_with_4_under_is_silent() -> void:
	var monster := Real.instance("EBP03-027")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {"hand": [Cards.battle(2), Cards.battle(2, 2000, "H2"), Cards.battle(2, 2000, "H3"),
			Cards.battle(2, 2000, "H4"), Cards.battle(2, 2000, "H5"), Cards.battle(2, 2000, "H6")]},
	})
	for i in range(4):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(state.players[1].hand.size()).is_equal(6)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP03-028: Thousand-Year Dragon King Ghidorah R4 — stack 5+ rank -3; opp counter: bury 3 → destroy z1-5 ≤5 ---


func test_ebp03_028_field_rank_minus_3_with_5_under_on_own_turn() -> void:
	var monster := Real.instance("EBP03-028")
	var opp_card := Cards.battle(6, 3000, "OPP")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: opp_card}},
	})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(3)
	state.current_player_id = 1
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(6)


func test_ebp03_028_opponent_counter_buries_3_and_destroys_zones_1_to_5() -> void:
	var monster := Real.instance("EBP03-028")
	var m1 := Cards.monster(1, 4000, [], "DM1")
	var m2 := Cards.monster(1, 4000, [], "DM2")
	var m3 := Cards.monster(2, 9000, [], "DM3")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {
			1: Cards.battle(4, 3000, "OPP-R4"),
			3: Cards.battle(6, 3000, "OPP-R6"),
			6: Cards.battle(3, 3000, "OPP-Z7"),
		}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	state.players[0].discard_pile.append_array([m1, m2, m3, Cards.battle(2, 2000, "BTL")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_cards": [[m1, m2, m3]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	var p1 := state.players[1]
	assert_int(p0.monster_stack.size()).is_equal(3)
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_bool(p1.zone_has_cards(1)).is_false()          # rank 4 in zones 1-5 destroyed
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP-R6")  # rank > 5 survives
	assert_str(str(p1.get_zone_top_card(6).get("id"))).is_equal("OPP-Z7")  # outside zones 1-5


func test_ebp03_028_silent_with_fewer_than_3_monsters_in_discard() -> void:
	var monster := Real.instance("EBP03-028")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {1: Cards.battle(4, 3000, "OPP-R4")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	state.players[0].discard_pile.append_array([Cards.monster(1, 4000, [], "DM1"), Cards.monster(1, 4000, [], "DM2")])
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_cards")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-029: Thousand-Year Dragon King Ghidorah R4 — invading w/ 7 under: choose one of three ---


func test_ebp03_029_field_rank_minus_3_with_5_under_on_own_turn() -> void:
	var monster := Real.instance("EBP03-029")
	var opp_card := Cards.battle(6, 3000, "OPP")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {2: opp_card}},
	})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_field_rank(opp_card, 1)).is_equal(3)


func test_ebp03_029_invading_choice_destroys_all_battle_cards_of_both_players() -> void:
	var monster := Real.instance("EBP03-029")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4, "zone_cards": {1: Cards.battle(3, 2000, "MINE")}},
		"p1": {"zone_cards": {2: Cards.battle(5, 3000, "OPP")}},
	})
	for i in range(7):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_bool(state.players[0].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(2)).is_false()


func test_ebp03_029_invading_choice_reduces_both_rages_by_2() -> void:
	var monster := Real.instance("EBP03-029")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4, "rage": 3},
		"p1": {"rage": 1},
	})
	for i in range(7):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(state.players[1].rage).is_equal(0)


func test_ebp03_029_invading_with_6_under_offers_no_choice() -> void:
	var monster := Real.instance("EBP03-029")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4, "zone_cards": {1: Cards.battle(3, 2000, "MINE")}},
	})
	for i in range(6):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_bool(state.players[0].zone_has_cards(1)).is_true()


# --- EBP03-030: SHIRASAGI : AC-3 — zone-8 Mechagodzilla +3000; enter: move a battle card ---


func test_ebp03_030_boosts_mechagodzilla_in_zone_8() -> void:
	var card := Real.instance("EBP03-030")
	var mecha := Cards.battle(4, 5000, "MECHA", [CardEnums.CardTrait.MECHAGODZILLA])
	var state := States.make_state({"p0": {"zone_cards": {2: card, 7: mecha}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 7)).is_equal(8000)

	# Non-Mechagodzilla in zone 8: no boost.
	var card2 := Real.instance("EBP03-030", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2, 7: Cards.battle(4, 5000, "PLAIN")}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_int(handler2.get_effective_zone_cp(0, 7)).is_equal(5000)


func test_ebp03_030_enter_moves_another_battle_card_to_empty_zone() -> void:
	var card := Real.instance("EBP03-030")
	var other := Cards.battle(3, 2000, "OTHER")
	var state := States.make_state({"p0": {"zone_cards": {2: card, 5: other}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [5, 4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(5)).is_false()
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal("OTHER")
	# Source pool excluded this card's own zone.
	assert_bool(2 in input.calls[0]["valid"]).is_false()


func test_ebp03_030_enter_skip_moves_nothing() -> void:
	var card := Real.instance("EBP03-030")
	var state := States.make_state({"p0": {"zone_cards": {2: card, 5: Cards.battle(3, 2000, "OTHER")}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[0].zone_has_cards(5)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(1)


# --- EBP03-032: Mechagodzilla(1974) — counter start adjacent: dump hand for +1000 CP each ---


func test_ebp03_032_counter_start_dumps_hand_for_temporary_cp() -> void:
	var card := Real.instance("EBP03-032")
	var state := States.make_state({"p0": {
		"zone_cards": {1: card},  # adjacent to monster zone 1 (idx 0)
		"hand": [Cards.battle(2, 2000, "H1"), Cards.battle(2, 2000, "H2"), Cards.strategy(2, "H3")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(3)
	# Base 3000 + 3 x 1000 on own turn.
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(6000)
	# The bonus is gated to the owner's turn.
	state.current_player_id = 1
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)


func test_ebp03_032_silent_when_not_adjacent_to_monster() -> void:
	var card := Real.instance("EBP03-032")
	var state := States.make_state({"p0": {
		"zone_cards": {4: card},  # zone 5: adjacent zones idx 3,5 — not monster idx 0
		"hand": [Cards.battle(2, 2000, "H1")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(3000)


# --- EBP03-034: Jet Jaguar(1973) — enter: discard strategy → opp -1 rage ---


func test_ebp03_034_enter_discards_strategy_to_drain_rage() -> void:
	var card := Real.instance("EBP03-034")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "hand": [Cards.battle(2, 2000, "BTL"), Cards.strategy(2, "S")]},
		"p1": {"rage": 1},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_that(input.calls[0]["valid"]).is_equal([1])


func test_ebp03_034_enter_without_strategy_or_skipped_is_silent() -> void:
	# No strategy in hand: no prompt.
	var card := Real.instance("EBP03-034")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "hand": [Cards.battle(2, 2000, "BTL")]},
		"p1": {"rage": 1},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(state.players[1].rage).is_equal(1)

	# Skipped: rage untouched.
	var card2 := Real.instance("EBP03-034", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {2: card2}, "hand": [Cards.strategy(2, "S")]},
		"p1": {"rage": 1},
	})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(1)


# --- EBP03-035: Satsuma — enter in opp monster column: discard strategy → advance to 6 ---


func test_ebp03_035_enter_in_column_discards_strategy_and_advances_to_6() -> void:
	# Card in zone 8 (idx 7) → opponent column zones [2, 7]; opp monster at zone 3.
	var card := Real.instance("EBP03-035")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "hand": [Cards.strategy(2, "S")], "monster_zone": 1},
		"p1": {"monster_zone": 3},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(6)
	assert_int(state.players[0].hand.size()).is_equal(0)


func test_ebp03_035_silent_when_out_of_column_or_already_at_6() -> void:
	# Wrong column: opponent monster at zone 4 (idx 3) — not in [2, 7].
	var card := Real.instance("EBP03-035")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "hand": [Cards.strategy(2, "S")]},
		"p1": {"monster_zone": 4},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(state.players[0].monster_zone).is_equal(1)

	# Monster already at zone 6+: no prompt.
	var card2 := Real.instance("EBP03-035", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {7: card2}, "hand": [Cards.strategy(2, "S")], "monster_zone": 6},
		"p1": {"monster_zone": 3},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)
	assert_int(state2.players[0].monster_zone).is_equal(6)


# --- EBP03-036: Moguera — enter from hand in zone 8: search + play a Moguera battle ---


func test_ebp03_036_enter_from_hand_in_zone_8_plays_moguera_from_deck() -> void:
	var card := Real.instance("EBP03-036")
	var target := Real.instance("EBP03-036", 1)
	var state := States.make_state({"p0": {
		"zone_cards": {7: card},
		"main_deck": [Cards.battle(3, 2000, "FILLER"), target],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}], "select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp03_036_silent_outside_zone_8_or_when_played_from_effect() -> void:
	# Not in zone 8: no search.
	var card := Real.instance("EBP03-036")
	var state := States.make_state({"p0": {
		"zone_cards": {3: card},
		"main_deck": [Real.instance("EBP03-036", 1)],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Played via an effect: no search even in zone 8.
	var card2 := Real.instance("EBP03-036", 2)
	var state2 := States.make_state({"p0": {
		"zone_cards": {7: card2},
		"main_deck": [Real.instance("EBP03-036", 3)],
	}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2, true)
	assert_int(input2.count_calls("search_cards")).is_equal(0)


# --- EBP03-037: Godzilla(2001) battle R6 — Awk8 enter +1 rage; Awk8 +5000 CP ---


func test_ebp03_037_awakening8_gains_rage_and_cp() -> void:
	var card := Real.instance("EBP03-037")
	var state := States.make_state({"p0": {"zone_cards": {0: card}, "monster_zone": 8}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(10000)


func test_ebp03_037_silent_below_awakening8() -> void:
	var card := Real.instance("EBP03-037")
	var state := States.make_state({"p0": {"zone_cards": {0: card}, "monster_zone": 7}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].rage).is_equal(0)
	assert_int(handler.get_effective_zone_cp(0, 0)).is_equal(5000)


# --- EBP03-038: MFS-3 battle R6 — counter start, opp rage 2+: destroy own adjacent cards ---


func test_ebp03_038_destroys_own_adjacent_cards_when_opponent_rage_2() -> void:
	var card := Real.instance("EBP03-038")
	var state := States.make_state({
		"p0": {"zone_cards": {
			3: card,
			2: Cards.battle(3, 2000, "ADJ-A"),
			6: Cards.battle(3, 2000, "ADJ-B"),
			1: Cards.battle(3, 2000, "SAFE"),
		}},
		"p1": {"rage": 2},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_bool(p0.zone_has_cards(6)).is_false()
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal("SAFE")
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(2)


func test_ebp03_038_silent_below_opponent_rage_2() -> void:
	var card := Real.instance("EBP03-038")
	var state := States.make_state({
		"p0": {"zone_cards": {3: card, 2: Cards.battle(3, 2000, "ADJ-A")}},
		"p1": {"rage": 1},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[0].zone_has_cards(2)).is_true()


# --- EBP03-039: Godzilla(2016) 4th Form — strategy discarded → draw; 5+ strategies in discard → +5000 ---


func test_ebp03_039_draws_when_own_strategy_hits_the_discard() -> void:
	var card := Real.instance("EBP03-039")
	var state := States.make_state({"p0": {
		"zone_cards": {1: card},
		"strategy_zones": [Cards.strategy(2, "S")],
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.discard_strategy_from_zone(0, 0)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("D1")
	assert_int(p0.discard_pile.size()).is_equal(1)


func test_ebp03_039_cp_bonus_with_5_strategies_in_discard() -> void:
	var card := Real.instance("EBP03-039")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}})
	var p0 := state.players[0]
	for i in range(4):
		p0.discard_pile.append(Cards.strategy(2, "DS-%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(5000)
	p0.discard_pile.append(Cards.strategy(2, "DS-4"))
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(10000)


# --- EBP03-040: Mechagodzilla(1975) R7 — counter start move; +3000 in opp monster column ---


func test_ebp03_040_counter_start_moves_to_chosen_empty_zone() -> void:
	var card := Real.instance("EBP03-040")
	var state := States.make_state({"p0": {"zone_cards": {4: card}}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[0].zone_has_cards(4)).is_false()
	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))


func test_ebp03_040_skip_stays_put_and_column_cp_bonus() -> void:
	var card := Real.instance("EBP03-040")
	# Zone 5 (idx 4) → opponent column zone 1; opp monster at zone 1 matches.
	var state := States.make_state({"p0": {"zone_cards": {4: card}}, "p1": {"monster_zone": 1}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_str(str(state.players[0].get_zone_top_card(4).get("id"))).is_equal(str(card.get("id")))
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(9000)
	state.players[1].monster_zone = 2
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(6000)


# --- EBP03-041: Godzilla(2023) battle R8 — enter rage drain; destroyed → deck bottom ---


func test_ebp03_041_enter_drains_2_rage_in_opponent_monster_column_with_rage_2() -> void:
	# Zone 8 (idx 7) → opponent column [2, 7]; opp monster zone 3 matches.
	var card := Real.instance("EBP03-041")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "rage": 2},
		"p1": {"monster_zone": 3, "rage": 4},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(2)


func test_ebp03_041_enter_silent_below_rage_2_or_wrong_column() -> void:
	# Own rage too low.
	var card := Real.instance("EBP03-041")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "rage": 1},
		"p1": {"monster_zone": 3, "rage": 4},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(4)

	# Wrong column: opp monster zone 4 not in [2, 7].
	var card2 := Real.instance("EBP03-041", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {7: card2}, "rage": 2},
		"p1": {"monster_zone": 4, "rage": 4},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(4)


func test_ebp03_041_destroyed_goes_to_deck_bottom_instead_of_discard() -> void:
	var card := Real.instance("EBP03-041")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("EBP03-041 should sit at the deck bottom after destruction") \
		.is_equal(str(card.get("id")))
