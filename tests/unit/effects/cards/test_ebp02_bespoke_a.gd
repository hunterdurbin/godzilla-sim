extends GdUnitTestSuite

## Tier C bespoke tests for EBP02 cards 003-040 — one-of-a-kind effects driven
## through the real trigger-dispatch seam (trigger_enter / trigger_when_invading /
## trigger_phase_start / destroy_zones / discard_strategy_from_zone / queries).
## See classification.md for the bespoke list. Cards 042-T04 live in
## test_ebp02_bespoke_b.gd.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


## A fresh token instance straight from the CardData template (tokens keep the
## bare template id — PlayerState.count_zone_tokens_by_id relies on that).
static func _token(token_id: String) -> Dictionary:
	return CardData.get_card_by_id(token_id).duplicate(true)


# --- EBP02-003: Burst3; enter w/ "Giant Unknown Creature" under → discard strategy → advance 1 ---


func test_ebp02_003_discards_strategy_to_advance_with_guc_under() -> void:
	var card := Real.instance("EBP02-003")
	var guc := Cards.monster(1, 4000, [], "GUC")
	guc["name"] = "Giant Unknown Creature"
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 2,
		"hand": [Cards.battle(2, 2000, "B"), Cards.strategy(2, "S")],
	}})
	state.players[0].monster_stack.append(guc)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(3)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("S")
	# Only strategy cards were offered as the cost.
	assert_array(input.calls[0]["valid"]).contains_exactly([1])
	assert_int(handler.queries.get_burst_rank(card)).is_equal(3)


func test_ebp02_003_silent_without_guc_under() -> void:
	var card := Real.instance("EBP02-003")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 2,
		"hand": [Cards.strategy(2, "S")],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)


# --- EBP02-006: invading w/ 3rd Form under → destroy all opp rank<=6; TL w/ 4th Form under ---


func test_ebp02_006_invading_with_third_form_under_destroys_rank6_and_lower() -> void:
	var card := Real.instance("EBP02-006")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(6, 4000, "R6"), 5: Cards.battle(7, 5000, "R7")}},
	})
	state.players[0].monster_stack.append(Cards.monster(3, 20000, [CardEnums.CardTrait.THIRD_FORM], "U3"))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(5).get("id"))).is_equal("R7")
	assert_int(p1.discard_pile.size()).is_equal(1)


func test_ebp02_006_invading_without_third_form_destroys_nothing() -> void:
	var card := Real.instance("EBP02-006")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(4, 4000, "R4")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_bool(state.players[1].zone_has_cards(1)).is_true()


func test_ebp02_006_threat_bonus_needs_fourth_form_under() -> void:
	var card := Real.instance("EBP02-006")
	var state := States.make_state({"p0": {"current_monster": card}})
	state.players[0].strategy_zones[0] = Cards.strategy(2, "S1")
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	# The card's own <4th Form> trait does not count — it must be UNDER the card.
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)

	state.players[0].monster_stack.append(Cards.monster(3, 20000, [CardEnums.CardTrait.FOURTH_FORM], "U4"))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(10000)

	state.players[0].strategy_zones[1] = Cards.strategy(2, "S2")
	assert_int(handler.get_threat_level_modifier(0)).is_equal(20000)


# --- EBP02-007: Burst3; enter: discard strategy → reveal 5, monster to hand, rest discarded ---


func test_ebp02_007_discards_strategy_then_digs_five_for_a_monster() -> void:
	var card := Real.instance("EBP02-007")
	var wanted := Cards.monster(2, 9000, [], "DIG-MON")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"hand": [Cards.strategy(2, "COST")],
		"main_deck": [
			Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2"), wanted,
			Cards.strategy(2, "D3"), Cards.battle(1, 2000, "D4"), Cards.battle(1, 2000, "BELOW"),
		],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "search_cards": [{"id": "DIG-MON"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("DIG-MON")
	assert_int(p0.main_deck.size()).is_equal(1)
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("BELOW")
	# Discard: the strategy cost + the 4 non-chosen revealed cards.
	assert_int(p0.discard_pile.size()).is_equal(5)
	# The pick pool only offered the monster from the reveal.
	assert_int(input.calls[1]["matching"].size()).is_equal(1)
	assert_int(handler.queries.get_burst_rank(card)).is_equal(3)


func test_ebp02_007_skipping_the_cost_skips_the_dig() -> void:
	var card := Real.instance("EBP02-007")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"hand": [Cards.strategy(2, "COST")],
		"main_deck": [Cards.monster(2, 9000, [], "DIG-MON")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP02-009: Burst3; burst discard → back to hand; invading → opp discards to 3 ---


func test_ebp02_009_invading_makes_opponent_discard_to_three() -> void:
	var card := Real.instance("EBP02-009")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"hand": [Cards.battle(1), Cards.battle(2), Cards.battle(3), Cards.strategy(2), Cards.strategy(3)]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[0, 1]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(state.players[1].hand.size()).is_equal(3)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(handler.queries.get_burst_rank(card)).is_equal(3)


func test_ebp02_009_burst_discard_returns_itself_to_hand() -> void:
	var card := Real.instance("EBP02-009")
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_burst_discard(0, card)

	var p0 := state.players[0]
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(card.get("id")))


# --- EBP02-010: enter: move 1 OTHER battle card to an unoccupied zone ---


func test_ebp02_010_moves_another_battle_card_to_empty_zone() -> void:
	var card := Real.instance("EBP02-010")
	var other := Cards.battle(3, 3000, "OTHER")
	var state := States.make_state({"p0": {"zone_cards": {2: card, 4: other}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4, 6]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(4)).is_false()
	assert_str(str(p0.get_zone_top_card(6).get("id"))).is_equal("OTHER")
	# Source pool excludes the card itself; destination pool excludes occupied
	# zones and the monster zone (idx 0).
	assert_array(input.calls[0]["valid"]).contains_exactly([4])
	assert_array(input.calls[1]["valid"]).contains_exactly([1, 3, 5, 6, 7])


func test_ebp02_010_silent_when_no_other_battle_cards() -> void:
	var card := Real.instance("EBP02-010")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-012: zone-8 strategy-discard interceptor; Awakening4 main start forced counter ---


func test_ebp02_012_intercepts_strategy_discard_in_zone_8_when_accepted() -> void:
	var card := Real.instance("EBP02-012")
	var strategy := Cards.strategy(2, "S")
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	state.players[0].strategy_zones[0] = strategy
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.discard_strategy_from_zone(0, 0)

	var p0 := state.players[0]
	assert_bool(p0.strategy_zones[0].is_empty()).is_true()
	assert_int(p0.get_zone_stack(7).size()).is_equal(2)
	assert_str(str(p0.get_zone_stack(7)[1].get("id"))).is_equal("S")
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp02_012_declined_interception_lets_strategy_go_to_discard() -> void:
	var card := Real.instance("EBP02-012")
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	state.players[0].strategy_zones[0] = Cards.strategy(2, "S")
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.discard_strategy_from_zone(0, 0)

	var p0 := state.players[0]
	assert_int(p0.get_zone_stack(7).size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("S")


func test_ebp02_012_does_not_intercept_outside_zone_8() -> void:
	var card := Real.instance("EBP02-012")
	var state := States.make_state({"p0": {"zone_cards": {3: card}}})
	state.players[0].strategy_zones[0] = Cards.strategy(2, "S")
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.discard_strategy_from_zone(0, 0)

	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("S")
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_ebp02_012_awakening4_main_start_forces_counter_with_two_under() -> void:
	var card := Real.instance("EBP02-012")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "monster_zone": 4},
		"p1": {"monster_zone": 7, "monster_deck": Cards.monster_line()},
	})
	state.players[0].zones[7].append(Cards.strategy(2, "U1"))
	state.players[0].zones[7].append(Cards.strategy(2, "U2"))
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	# Forced counter: opponent retreats 7 -> 4 and must rank up (1 -> 2).
	assert_int(state.players[1].monster_zone).is_equal(4)
	assert_int(state.players[1].current_monster.get("rank", -1)).is_equal(2)


func test_ebp02_012_phase_trigger_silent_without_awakening_or_stack() -> void:
	# No Awakening4: nothing happens despite 2 cards under.
	var card := Real.instance("EBP02-012")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "monster_zone": 3},
		"p1": {"monster_zone": 7, "monster_deck": Cards.monster_line()},
	})
	state.players[0].zones[7].append(Cards.strategy(2, "U1"))
	state.players[0].zones[7].append(Cards.strategy(2, "U2"))
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(state.players[1].monster_zone).is_equal(7)

	# Awakening4 but only 1 card under: still silent.
	var card2 := Real.instance("EBP02-012", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {7: card2}, "monster_zone": 4},
		"p1": {"monster_zone": 7, "monster_deck": Cards.monster_line()},
	})
	state2.players[0].zones[7].append(Cards.strategy(2, "U1"))
	state2.current_phase = CardEnums.GamePhase.MAIN
	state2.current_player_id = 0
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(state2.players[1].monster_zone).is_equal(7)


# --- EBP02-013: enter w/ rage>=2 → advance monster to zone 5 ---


func test_ebp02_013_advances_to_zone_5_with_rage_2() -> void:
	var card := Real.instance("EBP02-013")
	var state := States.make_state({"p0": {"rage": 2, "monster_zone": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(5)


func test_ebp02_013_silent_below_rage_2_or_past_zone_5() -> void:
	var card := Real.instance("EBP02-013")
	var state := States.make_state({"p0": {"rage": 1, "monster_zone": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[0].monster_zone).is_equal(2)

	var card2 := Real.instance("EBP02-013", 1)
	var state2 := States.make_state({"p0": {"rage": 3, "monster_zone": 6}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[0].monster_zone).is_equal(6)


# --- EBP02-019: move 1 battle card; advance 1 if invaded this turn ---


func test_ebp02_019_moves_battle_card_and_advances_after_invasion() -> void:
	var card := Real.instance("EBP02-019")
	var battle := Cards.battle(2, 2000, "B")
	var state := States.make_state({"p0": {
		"zone_cards": {1: battle}, "monster_zone": 3, "has_invaded_this_turn": true,
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 5]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(1)).is_false()
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal("B")
	assert_int(p0.monster_zone).is_equal(4)


func test_ebp02_019_no_move_pool_and_no_advance_without_invasion() -> void:
	var card := Real.instance("EBP02-019")
	var state := States.make_state({"p0": {"monster_zone": 3}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(3)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-020: 5+ strategies in discard → train bomber tokens in each empty zone ---


func test_ebp02_020_fills_empty_zones_with_tokens_and_token_enter_fires() -> void:
	var card := Real.instance("EBP02-020")
	# Only zone idx 7 is empty (monster occupies idx 0, battles in 1-6) so a
	# single token is created — keeps the standby batch single-entry.
	var state := States.make_state({
		"p0": {"monster_zone": 1, "zone_cards": {
			1: Cards.battle(1, 1000, "B1"), 2: Cards.battle(1, 1000, "B2"),
			3: Cards.battle(1, 1000, "B3"), 4: Cards.battle(1, 1000, "B4"),
			5: Cards.battle(1, 1000, "B5"), 6: Cards.battle(1, 1000, "B6"),
		}},
		"p1": {"rage": 2},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.strategy(2, "DS%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(7).get("id"))).is_equal("EBP02-T01")
	# The token's own <Enter> (reduce opp rage 1) resolves via the drained queue.
	assert_int(state.players[1].rage).is_equal(1)


func test_ebp02_020_silent_with_only_four_strategies_in_discard() -> void:
	var card := Real.instance("EBP02-020")
	var state := States.make_state({"p1": {"rage": 2}})
	for i in range(4):
		state.players[0].discard_pile.append(Cards.strategy(2, "DS%d" % i))
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "DB"))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[0].has_zone_matching(
		func(c: Dictionary) -> bool: return c.get("id", "") == "EBP02-T01")).is_false()
	assert_int(state.players[1].rage).is_equal(2)


# --- EBP02-022: invading → may play the blue battle discarded for the invade ---


func test_ebp02_022_replays_blue_battle_discarded_for_invasion() -> void:
	var card := Real.instance("EBP02-022")
	var blue := Cards.battle(3, 3000, "BLU")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 4}})
	state.players[0].discard_pile.append(blue)
	state.players[0].last_invasion_card = blue
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("BLU")
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp02_022_ignores_non_blue_invasion_cost() -> void:
	var card := Real.instance("EBP02-022")
	var red := Cards.battle(3, 3000, "RED")  # fixture battles are red
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 4}})
	state.players[0].discard_pile.append(red)
	state.players[0].last_invasion_card = red
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 4, 5)

	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-023: enter w/ 5+ monsters in discard → retreat weak opp monster; TL at 10+ ---


func test_ebp02_023_retreats_low_threat_opponent_with_five_monsters_discarded() -> void:
	var card := Real.instance("EBP02-023")
	var state := States.make_state({
		"p0": {"current_monster": card},
		"p1": {"monster_zone": 3},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].monster_zone).is_equal(2)


func test_ebp02_023_no_retreat_below_five_monsters_or_above_50k_threat() -> void:
	# Only 4 monsters in discard: silent.
	var card := Real.instance("EBP02-023")
	var state := States.make_state({"p0": {"current_monster": card}, "p1": {"monster_zone": 3}})
	for i in range(4):
		state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# 5 monsters but opponent threat > 50,000 (rage pumps it): silent.
	var card2 := Real.instance("EBP02-023", 1)
	var state2 := States.make_state({"p0": {"current_monster": card2}, "p1": {"monster_zone": 3, "rage": 10}})
	for i in range(5):
		state2.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM%d" % i))
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(3)


func test_ebp02_023_gains_10000_threat_with_ten_monsters_in_discard() -> void:
	var card := Real.instance("EBP02-023")
	var state := States.make_state({"p0": {"current_monster": card}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	for i in range(9):
		state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM%d" % i))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)

	state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM9"))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(10000)


# --- EBP02-025: cannot advance/invade; enter → Tentacles token adjacent ---


func test_ebp02_025_plays_tentacles_token_adjacent_and_blocks_movement() -> void:
	var card := Real.instance("EBP02-025")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 4}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(4).get("id"))).is_equal("EBP02-T02")
	assert_array(input.calls[0]["valid"]).contains_exactly([2, 4, 6])

	# can_monster_advance / can_monster_invade gate the movement queries...
	assert_bool(handler.is_monster_advance_blocked(0)).is_true()
	assert_bool(handler.is_own_invasion_blocked(0)).is_true()
	# ...and effect-driven advances are refused outright.
	await handler.advance_monster_to_zone(0, 6)
	assert_int(state.players[0].monster_zone).is_equal(4)


# --- EBP02-026: enter w/ strategy in play → destroy zone + adjacent (rank<=5) ---


func test_ebp02_026_destroys_chosen_zone_and_adjacent_rank5_and_lower() -> void:
	var card := Real.instance("EBP02-026")
	var state := States.make_state({
		"p0": {"current_monster": card},
		"p1": {"zone_cards": {
			3: Cards.battle(4, 3000, "HIT-A"),
			2: Cards.battle(4, 3000, "HIT-B"),
			6: Cards.battle(6, 5000, "ADJ-R6"),
			0: Cards.battle(3, 3000, "FAR"),
		}},
	})
	state.players[0].strategy_zones[0] = Cards.strategy(2, "S")
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(3)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_false()
	# Adjacent but rank 6: survives. Not adjacent: survives.
	assert_str(str(p1.get_zone_top_card(6).get("id"))).is_equal("ADJ-R6")
	assert_str(str(p1.get_zone_top_card(0).get("id"))).is_equal("FAR")


func test_ebp02_026_silent_without_strategy_or_targets() -> void:
	# No strategy in play.
	var card := Real.instance("EBP02-026")
	var state := States.make_state({
		"p0": {"current_monster": card},
		"p1": {"zone_cards": {3: Cards.battle(4, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_bool(state.players[1].zone_has_cards(3)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Strategy in play but no rank<=5 targets anywhere.
	var card2 := Real.instance("EBP02-026", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": card2},
		"p1": {"zone_cards": {3: Cards.battle(6, 5000, "R6")}},
	})
	state2.players[0].strategy_zones[0] = Cards.strategy(2, "S")
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_bool(state2.players[1].zone_has_cards(3)).is_true()
	assert_int(input2.count_calls("select_zone")).is_equal(0)


# --- EBP02-028: enter → play rank<=4 Evolution battle cards from discard adjacent (max 3) ---


func test_ebp02_028_plays_evolution_cards_from_discard_to_adjacent_zones() -> void:
	var monster := Real.instance("EBP02-028")
	var evo_a := Real.instance("EBP02-030")  # rank 1, Evolution5
	var evo_b := Real.instance("EBP02-032")  # rank 4, Evolution7
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4}})
	var p0 := state.players[0]
	p0.discard_pile.append_array([evo_a, evo_b, Cards.battle(3, 3000, "NO-EVO")])
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"search_cards": [{"id": evo_a.get("id")}],
		"select_zone": [2, 4],
	}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(evo_a.get("id")))
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal(str(evo_b.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("NO-EVO")
	# Pool only offered the Evolution battle cards.
	assert_int(input.calls[0]["matching"].size()).is_equal(2)
	# Zone choices are limited to the monster's adjacent zones.
	assert_array(input.calls[1]["valid"]).contains_exactly([2, 4, 6])


func test_ebp02_028_silent_without_evolution_cards_in_discard() -> void:
	var monster := Real.instance("EBP02-028")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4}})
	state.players[0].discard_pile.append(Cards.battle(3, 3000, "NO-EVO"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-030: Evolution5 <Little Godzilla> at main start ---


func test_ebp02_030_evolves_into_little_godzilla_at_own_main_start() -> void:
	var card := Real.instance("EBP02-030")
	var target := Real.instance("EBP02-033")  # Little Godzilla, rank 5 battle
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(2, 2000, "D1"), target],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	assert_int(p0.main_deck.size()).is_equal(1)
	# Only the trait+rank-matching card was offered.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp02_030_does_not_evolve_on_opponent_turn() -> void:
	var card := Real.instance("EBP02-030")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {2: card}, "main_deck": [Real.instance("EBP02-033")]},
	})
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP02-032: Evolution7 <Biollante> at main start ---


func test_ebp02_032_evolves_into_biollante_battle_at_own_main_start() -> void:
	var card := Real.instance("EBP02-032")
	var target := Real.instance("EBP02-032", 1)  # another Biollante battle (rank 4 <= 7)
	var state := States.make_state({"p0": {
		"zone_cards": {3: card},
		"main_deck": [target, Cards.battle(2, 2000, "D1")],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(3).size()).is_equal(2)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp02_032_wrong_phase_does_not_evolve() -> void:
	var card := Real.instance("EBP02-032")
	var state := States.make_state({"p0": {
		"zone_cards": {3: card},
		"main_deck": [Real.instance("EBP02-032", 1)],
	}})
	state.current_phase = CardEnums.GamePhase.END
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(state.players[0].get_zone_stack(3).size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP02-035: enter: 2+ Biollante in discard → recycle opp discard; play 2 Tentacles adjacent ---


func test_ebp02_035_recycles_opponent_discard_and_plays_two_tentacles() -> void:
	var card := Real.instance("EBP02-035")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"main_deck": [Cards.battle(1, 1000, "OD")]},
	})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "BIO1", [CardEnums.CardTrait.BIOLLANTE]))
	state.players[0].discard_pile.append(Cards.battle(3, 3000, "BIO2", [CardEnums.CardTrait.BIOLLANTE]))
	state.players[1].discard_pile.append_array([
		Cards.battle(1, 1000, "X1"), Cards.battle(1, 1000, "X2"), Cards.strategy(2, "X3"),
	])
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].discard_pile.size()).is_equal(0)
	assert_int(state.players[1].main_deck.size()).is_equal(4)
	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal("EBP02-T02")
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal("EBP02-T02")
	# Rule 5.11.1.3: the second token must go to a different adjacent zone.
	assert_array(input.calls[1]["valid"]).contains_exactly([3, 7])


func test_ebp02_035_one_biollante_skips_recycle_and_skip_stops_tokens() -> void:
	var card := Real.instance("EBP02-035")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "BIO1", [CardEnums.CardTrait.BIOLLANTE]))
	state.players[1].discard_pile.append(Cards.battle(1, 1000, "X1"))
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].discard_pile.size()).is_equal(1)
	assert_int(input.count_calls("select_zone")).is_equal(1)
	assert_bool(state.players[0].zone_has_cards(1)).is_false()


# --- EBP02-037: enter: draw 2 then discard 2 ---


func test_ebp02_037_draws_two_then_discards_two() -> void:
	var card := Real.instance("EBP02-037")
	var state := States.make_state({"p0": {
		"hand": [Cards.battle(1, 1000, "KEEP")],
		"main_deck": [Cards.battle(1, 1000, "D1"), Cards.battle(1, 1000, "D2"), Cards.battle(1, 1000, "D3")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[1, 2]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("KEEP")
	assert_int(p0.main_deck.size()).is_equal(1)
	assert_int(p0.discard_pile.size()).is_equal(2)


# --- EBP02-038: choose: destroy rank<=5 OR (10+ monsters discarded) destroy zone 8 ---


func test_ebp02_038_single_option_destroys_rank5_without_choice_prompt() -> void:
	var card := Real.instance("EBP02-038")
	var state := States.make_state({"p1": {"zone_cards": {
		1: Cards.battle(5, 4000, "R5"), 5: Cards.battle(6, 5000, "R6"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_str(str(state.players[1].get_zone_top_card(5).get("id"))).is_equal("R6")
	assert_int(input.count_calls("choose_option")).is_equal(0)
	# R6 was never offered as a destroy target.
	assert_array(input.calls[0]["valid"]).contains_exactly([1])


func test_ebp02_038_ten_monsters_unlock_zone8_destruction() -> void:
	var card := Real.instance("EBP02-038")
	var state := States.make_state({"p1": {"zone_cards": {
		7: Cards.battle(7, 6000, "Z8"), 1: Cards.battle(3, 3000, "R3"),
	}}})
	for i in range(10):
		state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(7)).is_false()
	assert_str(str(state.players[1].get_zone_top_card(1).get("id"))).is_equal("R3")
	assert_int(input.calls[0]["options"].size()).is_equal(2)


func test_ebp02_038_silent_with_no_available_option() -> void:
	var card := Real.instance("EBP02-038")
	var state := States.make_state({"p1": {"zone_cards": {5: Cards.battle(6, 5000, "R6")}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(5)).is_true()
	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-040: 5+ MB Weapon battle cards → dump hand, draw 5 ---


func test_ebp02_040_refreshes_hand_with_five_mb_weapons_in_zones() -> void:
	var card := Real.instance("EBP02-040")
	var zone_cards := {}
	for i in range(5):
		# Fixture name is "Test Battle MB-i" — contains "MB", carries Weapon.
		zone_cards[i + 1] = Cards.battle(2, 2000, "MB-%d" % i, [CardEnums.CardTrait.WEAPON])
	var deck: Array[Dictionary] = []
	for i in range(5):
		deck.append(Cards.battle(1, 1000, "N%d" % i))
	var state := States.make_state({"p0": {
		"zone_cards": zone_cards,
		"hand": [Cards.battle(1, 1000, "OLD1"), Cards.strategy(2, "OLD2")],
		"main_deck": deck,
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(5)
	assert_int(p0.discard_pile.size()).is_equal(2)
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp02_040_silent_with_only_four_matching_weapons() -> void:
	var card := Real.instance("EBP02-040")
	var zone_cards := {}
	for i in range(4):
		zone_cards[i + 1] = Cards.battle(2, 2000, "MB-%d" % i, [CardEnums.CardTrait.WEAPON])
	# Fifth weapon lacks "MB" in its name.
	zone_cards[5] = Cards.battle(2, 2000, "XW", [CardEnums.CardTrait.WEAPON])
	var state := States.make_state({"p0": {
		"zone_cards": zone_cards,
		"hand": [Cards.battle(1, 1000, "OLD1")],
		"main_deck": [Cards.battle(1, 1000, "N1")],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("OLD1")
	assert_int(input.count_calls("choose_hand_discards")).is_equal(0)
