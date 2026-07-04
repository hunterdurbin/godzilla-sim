extends GdUnitTestSuite

## Tier C bespoke tests for EBP03 cards 042-080 — one-of-a-kind effects driven
## through the real trigger-dispatch seam (trigger_* / destroy_zones /
## collect_* + resolve_deferred_entries / aggregation queries).
## Cards 001-041 live in test_ebp03_bespoke_a.gd; see classification.md.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


# --- EBP03-042: Ghogo — own invasion, in zone 8: tuck under a Mothra Evolution card + evolve it ---


func test_ebp03_042_tucks_under_mothra_and_evolves_on_own_invasion() -> void:
	var card := Real.instance("EBP03-042")
	var larva := Real.instance("EBP03-044")   # Evolution7 <Mothra>
	var imago := Real.instance("EBP03-045")   # rank 4 Mothra battle
	var state := States.make_state({"p0": {
		"zone_cards": {7: card, 2: larva},
		"main_deck": [Cards.battle(2, 2000, "FILLER"), imago],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2], "search_cards": [{"id": imago.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_invasion_observed(0, 1, 2)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_int(p0.get_zone_stack(2).size()).is_equal(3)
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(imago.get("id")))
	# Ghogo sits at the bottom of the evolved stack.
	assert_str(str(p0.get_zone_stack(2)[2].get("id"))).is_equal(str(card.get("id")))


func test_ebp03_042_silent_outside_zone_8_or_when_skipped() -> void:
	# Not in zone 8: no prompt.
	var card := Real.instance("EBP03-042")
	var larva := Real.instance("EBP03-044")
	var state := States.make_state({"p0": {"zone_cards": {3: card, 2: larva}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_invasion_observed(0, 1, 2)
	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_bool(state.players[0].zone_has_cards(3)).is_true()

	# Skipped: card stays in zone 8.
	var card2 := Real.instance("EBP03-042", 1)
	var larva2 := Real.instance("EBP03-044", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {7: card2, 2: larva2}}})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_zone": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_invasion_observed(0, 1, 2)
	assert_bool(state2.players[0].zone_has_cards(7)).is_true()
	assert_int(state2.players[0].get_zone_stack(2).size()).is_equal(1)


# --- EBP03-043: Star Falcon — Awk4 counter start: tuck under Land Moguera + play Moguera on top ---


func test_ebp03_043_tucks_under_land_moguera_and_plays_moguera_on_top() -> void:
	var card := Real.instance("EBP03-043")
	var land := Real.instance("EBP03-046")    # "Land Moguera"
	var target := Real.instance("EBP03-052")  # <Moguera> battle (enter is Awk6-gated, inert here)
	var state := States.make_state({"p0": {
		"monster_zone": 4,
		"zone_cards": {0: card, 5: land},
		"main_deck": [Cards.battle(2, 2000, "FILLER"), target],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [5], "search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(0)).is_false()
	assert_int(p0.get_zone_stack(5).size()).is_equal(3)
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal(str(target.get("id")))
	assert_str(str(p0.get_zone_stack(5)[1].get("id"))).is_equal(str(land.get("id")))
	assert_str(str(p0.get_zone_stack(5)[2].get("id"))).is_equal(str(card.get("id")))


func test_ebp03_043_silent_below_awakening4_or_without_land_moguera() -> void:
	# Below Awakening4: no prompt.
	var card := Real.instance("EBP03-043")
	var land := Real.instance("EBP03-046")
	var state := States.make_state({"p0": {"monster_zone": 3, "zone_cards": {0: card, 5: land}}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# No Land Moguera in zones: no prompt.
	var card2 := Real.instance("EBP03-043", 1)
	var state2 := States.make_state({"p0": {"monster_zone": 4, "zone_cards": {0: card2}}})
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input2.count_calls("select_zone")).is_equal(0)
	assert_bool(state2.players[0].zone_has_cards(0)).is_true()


# --- EBP03-046: Land Moguera — Awk4 enter w/ Star Falcon: destroy opp strategy OR drain rage ---


func test_ebp03_046_enter_choice_destroys_opponent_strategy() -> void:
	var card := Real.instance("EBP03-046")
	var falcon := Real.instance("EBP03-043")
	var state := States.make_state({
		"p0": {"monster_zone": 4, "zone_cards": {5: card, 1: falcon}},
		"p1": {"rage": 1, "strategy_zones": [Cards.strategy(2, "OPP-S")]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_strategy": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].strategy_zones[0].is_empty()).is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(1)
	assert_int(state.players[1].rage).is_equal(1)


func test_ebp03_046_enter_choice_reduces_opponent_rage() -> void:
	var card := Real.instance("EBP03-046")
	var falcon := Real.instance("EBP03-043")
	var state := States.make_state({
		"p0": {"monster_zone": 4, "zone_cards": {5: card, 1: falcon}},
		"p1": {"rage": 1, "strategy_zones": [Cards.strategy(2, "OPP-S")]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(0)
	assert_bool(state.players[1].strategy_zones[0].is_empty()).is_false()


func test_ebp03_046_enter_silent_without_star_falcon_or_awakening() -> void:
	# No Star Falcon: silent.
	var card := Real.instance("EBP03-046")
	var state := States.make_state({
		"p0": {"monster_zone": 4, "zone_cards": {5: card}},
		"p1": {"rage": 1, "strategy_zones": [Cards.strategy(2, "OPP-S")]},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(state.players[1].rage).is_equal(1)

	# Below Awakening4: silent.
	var card2 := Real.instance("EBP03-046", 1)
	var falcon2 := Real.instance("EBP03-043", 1)
	var state2 := States.make_state({
		"p0": {"monster_zone": 3, "zone_cards": {5: card2, 1: falcon2}},
		"p1": {"rage": 1},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(input2.count_calls("choose_option")).is_equal(0)


# --- EBP03-047: Garuda — counter start in opp monster column: discard Weapon/Mech → play Super MG on top ---


func test_ebp03_047_discards_weapon_and_stacks_super_mechagodzilla_on_top() -> void:
	# Zone 5 (idx 4) → opponent column zone 1; opp monster at zone 1 matches.
	var card := Real.instance("EBP03-047")
	var cost := Cards.battle(3, 2000, "WPN-COST", [CardEnums.CardTrait.WEAPON])
	var target := Real.instance("EBP03-053")  # "Super Mechagodzilla" battle
	var state := States.make_state({"p0": {
		"zone_cards": {4: card},
		"hand": [cost, Cards.battle(3, 2000, "PLAIN")],
		"main_deck": [Cards.battle(2, 2000, "FILLER"), target],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(4).size()).is_equal(2)
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("WPN-COST")
	# Only the Weapon/Mech battle card was a legal cost.
	assert_that(input.calls[0]["valid"]).is_equal([0])


func test_ebp03_047_silent_out_of_column_and_skippable() -> void:
	# Wrong column: opponent monster at zone 4.
	var card := Real.instance("EBP03-047")
	var state := States.make_state({
		"p0": {"zone_cards": {4: card}, "hand": [Cards.battle(3, 2000, "WPN", [CardEnums.CardTrait.WEAPON])]},
		"p1": {"monster_zone": 4},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Skipping the discard skips the search.
	var card2 := Real.instance("EBP03-047", 1)
	var state2 := States.make_state({"p0": {
		"zone_cards": {4: card2},
		"hand": [Cards.battle(3, 2000, "WPN", [CardEnums.CardTrait.WEAPON])],
		"main_deck": [Real.instance("EBP03-053", 1)],
	}})
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input2.count_calls("search_cards")).is_equal(0)
	assert_int(state2.players[0].hand.size()).is_equal(1)


# --- EBP03-048: Mechagodzilla(1993) — enter w/ 2+ other battle cards: opp -1 rage ---


func test_ebp03_048_enter_reduces_rage_with_2_other_battle_cards() -> void:
	var card := Real.instance("EBP03-048")
	var state := States.make_state({
		"p0": {"zone_cards": {3: card, 1: Cards.battle(2, 2000, "A"), 5: Cards.battle(2, 2000, "B")}},
		"p1": {"rage": 1},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(0)


func test_ebp03_048_enter_silent_with_only_1_other_battle_card() -> void:
	var card := Real.instance("EBP03-048")
	var state := States.make_state({
		"p0": {"zone_cards": {3: card, 1: Cards.battle(2, 2000, "A")}},
		"p1": {"rage": 1},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)


# --- EBP03-050: Rainbow Mothra — enter w/ Base: retreat 20k-or-less monster; main start Evolution8 ---


func test_ebp03_050_enter_with_base_retreats_low_threat_monster() -> void:
	var card := Real.instance("EBP03-050")
	var base := Cards.strategy(3, "BASE")
	base["is_base"] = true
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "strategy_zones": [base]},
		"p1": {"monster_zone": 3},  # fixture monster: 5000 TL, rage 0
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(2)


func test_ebp03_050_enter_silent_without_base_or_above_20k() -> void:
	# No Base: no retreat.
	var card := Real.instance("EBP03-050")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# Threat above 20,000 (5000 + 4 rage x 5000): no retreat.
	var card2 := Real.instance("EBP03-050", 1)
	var base2 := Cards.strategy(3, "BASE2")
	base2["is_base"] = true
	var state2 := States.make_state({
		"p0": {"zone_cards": {2: card2}, "strategy_zones": [base2]},
		"p1": {"monster_zone": 3, "rage": 4},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(3)


func test_ebp03_050_main_phase_start_evolves_itself() -> void:
	var card := Real.instance("EBP03-050")
	var target := Real.instance("EBP03-054")  # rank 8 Mothra battle (enter is zone-8 gated)
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(2, 2000, "FILLER"), target],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# Search pool offered only the Mothra battle card.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP03-051: Godzilla Jr. — stacks on Little Godzilla at -2 rank; +5000 CP per under-card ---


func test_ebp03_051_stacks_with_rank_discount_only_on_little_godzilla() -> void:
	var card := Real.instance("EBP03-051")
	var little := Cards.battle(5, 3000, "LG", [CardEnums.CardTrait.LITTLE_GODZILLA])
	var state := States.make_state({"p0": {
		"hand": [card],
		"zone_cards": {2: little, 3: Cards.battle(5, 3000, "PLAIN")},
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_bool(handler.should_stack_on_play(0, card, 2)).is_true()
	assert_int(handler.get_zone_play_rank_modifier(0, card, 2)).is_equal(-2)
	assert_bool(handler.should_stack_on_play(0, card, 3)).is_false()
	assert_int(handler.get_zone_play_rank_modifier(0, card, 3)).is_equal(0)
	# Stacking cards skip their self-modifier in the flat hand-play query.
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_ebp03_051_gains_5000_cp_per_card_under_it() -> void:
	var card := Real.instance("EBP03-051")
	var state := States.make_state({"p0": {"zone_cards": {4: Cards.battle(2, 2000, "U2")}}})
	var p0 := state.players[0]
	p0.push_zone_card(4, Cards.battle(3, 2000, "U1"))
	p0.push_zone_card(4, card)
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(16000)
	# No cards under: base CP only.
	var card2 := Real.instance("EBP03-051", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {4: card2}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	assert_int(handler2.get_effective_zone_cp(0, 4)).is_equal(6000)


# --- EBP03-052: M.O.G.U.E.R.A. — destroyed: under-cards to hand; Awk6 enter: tuck Land Moguera + Star Falcon ---


func test_ebp03_052_destroyed_returns_under_cards_to_hand() -> void:
	var card := Real.instance("EBP03-052")
	var state := States.make_state({"p0": {"zone_cards": {3: Cards.battle(2, 2000, "U2")}}})
	var p0 := state.players[0]
	p0.push_zone_card(3, Cards.battle(3, 2000, "U1"))
	p0.push_zone_card(3, card)
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(p0, [3])

	assert_bool(p0.zone_has_cards(3)).is_false()
	assert_int(p0.hand.size()).is_equal(2)
	# Only M.O.G.U.E.R.A. itself reaches the discard (destruction proceeds).
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp03_052_awakening6_enter_tucks_land_moguera_and_star_falcon() -> void:
	var card := Real.instance("EBP03-052")
	var land := Real.instance("EBP03-046")
	var falcon := Real.instance("EBP03-043")
	var state := States.make_state({"p0": {
		"monster_zone": 6,
		"zone_cards": {1: card},
		"main_deck": [land, falcon, Cards.battle(2, 2000, "FILLER")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": land.get("id")}, {"id": falcon.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.get_zone_stack(1).size()).is_equal(3)
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.main_deck.size()).is_equal(1)
	# Each search pool held exactly the named card.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)
	assert_int(input.calls[1]["matching"].size()).is_equal(1)


func test_ebp03_052_enter_silent_below_awakening6_or_with_cards_under() -> void:
	# Below Awakening6: no searches.
	var card := Real.instance("EBP03-052")
	var state := States.make_state({"p0": {
		"monster_zone": 5, "zone_cards": {1: card},
		"main_deck": [Real.instance("EBP03-046", 1)],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Cards already under: no searches.
	var card2 := Real.instance("EBP03-052", 1)
	var state2 := States.make_state({"p0": {
		"monster_zone": 6, "zone_cards": {1: Cards.battle(2, 2000, "UNDER")},
		"main_deck": [Real.instance("EBP03-046", 2)],
	}})
	state2.players[0].push_zone_card(1, card2)
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(input2.count_calls("search_cards")).is_equal(0)


# --- EBP03-053: Super Mechagodzilla — indestructible by opp effects at rage 0; column CP per opp rage ---


func test_ebp03_053_opponent_effect_cannot_destroy_it_while_opponent_rage_0() -> void:
	var card := Real.instance("EBP03-053")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	# Simulate an active opponent effect causing the destruction.
	handler.exec.active_player_id = 1
	handler.exec.active_card = {"id": "FAKE-OPP-EFFECT"}

	await handler.destroy_zones(state.players[0], [2])

	assert_bool(state.players[0].zone_has_cards(2)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_ebp03_053_destroyed_by_opponent_effect_once_opponent_has_rage() -> void:
	var card := Real.instance("EBP03-053")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"rage": 1}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.active_player_id = 1
	handler.exec.active_card = {"id": "FAKE-OPP-EFFECT"}

	await handler.destroy_zones(state.players[0], [2])

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_ebp03_053_rules_based_destruction_ignores_the_protection() -> void:
	# No active effect (rules-based cause): the caused_by_opponent gate fails
	# and the card is destructible even at opponent rage 0.
	var card := Real.instance("EBP03-053")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	assert_bool(state.players[0].zone_has_cards(2)).is_false()


func test_ebp03_053_gains_3000_cp_per_opponent_rage_in_monster_column() -> void:
	var card := Real.instance("EBP03-053")
	# Zone 3 (idx 2) → opponent column [2, 7]; opp monster zone 3 matches.
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 3, "rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(14000)
	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000)


# --- EBP03-054: Eternal Mothra — enter in zone 8 w/ Base: retreat 60k-or-less monster ---


func test_ebp03_054_enter_in_zone_8_with_base_retreats_opponent() -> void:
	var card := Real.instance("EBP03-054")
	var base := Cards.strategy(3, "BASE")
	base["is_base"] = true
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "strategy_zones": [base]},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(2)


func test_ebp03_054_enter_silent_outside_zone_8_or_without_base() -> void:
	# Wrong zone: no retreat.
	var card := Real.instance("EBP03-054")
	var base := Cards.strategy(3, "BASE")
	base["is_base"] = true
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "strategy_zones": [base]},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# No Base: no retreat.
	var card2 := Real.instance("EBP03-054", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {7: card2}},
		"p1": {"monster_zone": 3},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(3)


# --- EBP03-057: Desghidorah — enter w/ 3+ opp empty zones: destroy a strategy; CP vs no strategies ---


func test_ebp03_057_enter_destroys_opponent_strategy_with_3_empty_zones() -> void:
	var card := Real.instance("EBP03-057")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"strategy_zones": [Cards.strategy(2, "OPP-S")]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_strategy": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].strategy_zones[0].is_empty()).is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


func test_ebp03_057_enter_silent_with_fewer_than_3_empty_opponent_zones() -> void:
	var card := Real.instance("EBP03-057")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {
			"strategy_zones": [Cards.strategy(2, "OPP-S")],
			"zone_cards": {
				1: Cards.battle(2, 2000, "F1"), 2: Cards.battle(2, 2000, "F2"),
				3: Cards.battle(2, 2000, "F3"), 4: Cards.battle(2, 2000, "F4"),
				5: Cards.battle(2, 2000, "F5"), 6: Cards.battle(2, 2000, "F6"),
			},
		},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("select_strategy")).is_equal(0)
	assert_bool(state.players[1].strategy_zones[0].is_empty()).is_false()


func test_ebp03_057_cp_bonus_only_while_opponent_has_no_strategies() -> void:
	var card := Real.instance("EBP03-057")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)
	state.players[1].strategy_zones[0] = Cards.strategy(2, "OPP-S")
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(2000)


# --- EBP03-058: Zilla — end phase horizontal move; self-destructs next to own monster ---


func test_ebp03_058_moves_horizontally_and_survives_away_from_monster() -> void:
	var card := Real.instance("EBP03-058")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)
	# Back-row horizontal neighbours only (zone 3 → zones 2 and 4).
	assert_that(input.calls[0]["valid"]).is_equal([1, 3])


func test_ebp03_058_self_destructs_when_moving_next_to_own_monster() -> void:
	# Monster in zone 1 (idx 0); moving from idx 2 to idx 1 lands adjacent.
	var card := Real.instance("EBP03-058")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(1)).is_false()
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


# --- EBP03-059: Cretaceous King Ghidorah(1998) — Revenge: recover King Ghidorah monster ---


func test_ebp03_059_revenge_returns_king_ghidorah_monster_from_discard() -> void:
	var card := Real.instance("EBP03-059")
	var kg := Cards.monster(2, 9000, [CardEnums.CardTrait.KING_GHIDORAH], "KG-MON")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}})
	state.players[0].discard_pile.append_array([kg, Cards.monster(2, 9000, [CardEnums.CardTrait.MOTHRA], "OTHER-MON")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "KG-MON"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [1])

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("KG-MON")
	# Pool was trait-filtered: the Mothra monster was not offered.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp03_059_revenge_with_no_king_ghidorah_recovers_nothing() -> void:
	var card := Real.instance("EBP03-059")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}})
	state.players[0].discard_pile.append(Cards.monster(2, 9000, [CardEnums.CardTrait.MOTHRA], "OTHER-MON"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [1])

	assert_int(state.players[0].hand.size()).is_equal(0)


# --- EBP03-060: Mothra(imago)(1961) — Revenge: opp -1 rage ---


func test_ebp03_060_revenge_reduces_opponent_rage() -> void:
	var card := Real.instance("EBP03-060")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}, "p1": {"rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.destroy_zones(state.players[0], [1])
	assert_int(state.players[1].rage).is_equal(1)

	# At rage 0 the revenge has nothing to drain.
	var card2 := Real.instance("EBP03-060", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {1: card2}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.destroy_zones(state2.players[0], [1])
	assert_int(state2.players[1].rage).is_equal(0)


# --- EBP03-061: Dagahra — discarded for invasion: play from discard; Awk6 +3000 CP ---


func test_ebp03_061_plays_itself_from_discard_after_invasion_discard() -> void:
	var card := Real.instance("EBP03-061")
	var state := States.make_state({"p0": {"monster_zone": 4}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	var entries: Array = handler.collect_discarded_for_invasion_entries(0, card)
	assert_int(entries.size()).is_equal(1)
	await handler.resolve_deferred_entries(entries)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp03_061_fixture_cards_collect_no_invasion_discard_entries() -> void:
	var state := States.make_state({})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	var entries: Array = handler.collect_discarded_for_invasion_entries(0, Cards.battle(3, 2000, "PLAIN"))
	assert_int(entries.size()).is_equal(0)


func test_ebp03_061_gains_3000_cp_at_awakening6() -> void:
	var card := Real.instance("EBP03-061")
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "monster_zone": 6}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(6000)
	state.players[0].monster_zone = 5
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(3000)


# --- EBP03-062: Baragon(2001) — opp invasion destroys it; Revenge recovers a Guardian Beast ---


func test_ebp03_062_opponent_invasion_destroys_it_and_revenge_recovers_monster() -> void:
	var card := Real.instance("EBP03-062")
	var beast := Real.instance("EBP03-024")  # Sacred Guardian Beasts monster (no effect script)
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {2: card}},
	})
	state.players[0].discard_pile.append(beast)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": beast.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_invasion_observed(1, 1, 2)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(beast.get("id")))
	# Baragon itself stayed in the discard.
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp03_062_own_invasion_leaves_it_alone() -> void:
	var card := Real.instance("EBP03-062")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_invasion_observed(0, 1, 2)

	assert_bool(state.players[0].zone_has_cards(2)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


# --- EBP03-063: King Ghidorah(1998) — own turn Awk4: play from discard when monster played ---


func test_ebp03_063_plays_from_discard_when_monster_played_at_awakening4() -> void:
	var card := Real.instance("EBP03-063")
	var state := States.make_state({"p0": {"monster_zone": 4}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_monster_played(0, {}, state.players[0].current_monster)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp03_063_stays_in_discard_below_awakening4_or_on_opponent_turn() -> void:
	# Below Awakening4: no zone prompt.
	var card := Real.instance("EBP03-063")
	var state := States.make_state({"p0": {"monster_zone": 3}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_monster_played(0, {}, state.players[0].current_monster)
	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)

	# Opponent's turn: gated off.
	var card2 := Real.instance("EBP03-063", 1)
	var state2 := States.make_state({"current_player_id": 1, "p0": {"monster_zone": 4}})
	state2.players[0].discard_pile.append(card2)
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_monster_played(0, {}, state2.players[0].current_monster)
	assert_int(input2.count_calls("select_zone")).is_equal(0)
	assert_int(state2.players[0].discard_pile.size()).is_equal(1)


# --- EBP03-064: Mothra(imago)(2001) R7 — enter tucks discard battle; Awk4/Awk6 CP with under-card ---


func test_ebp03_064_enter_tucks_battle_from_discard_after_opponent_loss() -> void:
	var card := Real.instance("EBP03-064")
	var buried := Cards.battle(3, 2000, "TUCK")
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "monster_zone": 4}})
	state.players[1].cards_destroyed_this_turn.append(Cards.battle(2, 2000, "DEAD"))
	state.players[0].discard_pile.append(buried)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "TUCK"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.get_zone_stack(1).size()).is_equal(2)
	assert_int(p0.discard_pile.size()).is_equal(0)
	# Awakening4: +3000; Awakening6 adds another +3000.
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(9000)
	p0.monster_zone = 6
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(12000)
	p0.monster_zone = 3
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(6000)


func test_ebp03_064_enter_silent_without_opponent_destruction_and_no_cp_without_under() -> void:
	var card := Real.instance("EBP03-064")
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "monster_zone": 6}})
	state.players[0].discard_pile.append(Cards.battle(3, 2000, "TUCK"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("search_cards")).is_equal(0)
	# Awakening6 but nothing under: no CP bonus.
	assert_int(handler.get_effective_zone_cp(0, 1)).is_equal(6000)


# --- EBP03-066: Thousand-Year Dragon King Ghidorah — -2 hand rank vs 2 strategies; enter destroys one ---


func test_ebp03_066_hand_rank_discount_with_2_opponent_strategies() -> void:
	var card := Real.instance("EBP03-066")
	var state := States.make_state({
		"p0": {"hand": [card]},
		"p1": {"strategy_zones": [Cards.strategy(2, "S1"), Cards.strategy(2, "S2")]},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-2)
	state.players[1].strategy_zones[1] = {}
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_ebp03_066_enter_destroys_chosen_opponent_strategy() -> void:
	var card := Real.instance("EBP03-066")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"strategy_zones": [Cards.strategy(2, "S1"), Cards.strategy(2, "S2")]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_strategy": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].strategy_zones[1].is_empty()).is_true()
	assert_bool(state.players[1].strategy_zones[0].is_empty()).is_false()
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


func test_ebp03_066_enter_silent_without_opponent_strategies() -> void:
	var card := Real.instance("EBP03-066")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(input.count_calls("select_strategy")).is_equal(0)


# --- EBP03-067: Monster X — own-turn discard w/ 2+ zone colors: plays itself + destroys lowest rank ---


func test_ebp03_067_discard_plays_itself_and_destroys_lowest_ranked_card() -> void:
	var card := Real.instance("EBP03-067")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"p0": {"zone_cards": {1: Cards.battle(2, 2000, "RED"), 2: blue}},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP-R3"), 3: Cards.battle(5, 3000, "OPP-R5")}},
	})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4, 1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_discard_from_hand(0, card)

	var p0 := state.players[0]
	var p1 := state.players[1]
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP-R5")
	# Only the lowest-ranked card was offered for destruction.
	assert_that(input.calls[1]["valid"]).is_equal([1])
	# Variable CP: 3000 x 2 colors among OTHER battle cards.
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(6000)


func test_ebp03_067_stays_in_discard_with_fewer_than_2_colors() -> void:
	var card := Real.instance("EBP03-067")
	var state := States.make_state({
		"p0": {"zone_cards": {1: Cards.battle(2, 2000, "RED-A"), 2: Cards.battle(2, 2000, "RED-B")}},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}},
	})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_discard_from_hand(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


func test_ebp03_067_stays_in_discard_on_opponent_turn() -> void:
	var card := Real.instance("EBP03-067")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {1: Cards.battle(2, 2000, "RED"), 2: blue}},
	})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_discard_from_hand(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_ebp03_067_invasion_crush_does_not_recheck_color_condition() -> void:
	# Ruling: the 2-color condition is checked once, when the card is discarded
	# as the invasion cost — NOT re-checked after movement/crush. Here the
	# invasion crushes RED (one of the two colors), and Monster X still plays.
	var card := Real.instance("EBP03-067")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"p0": {
			"hand": [card],
			"monster_zone": 1,
			"zone_cards": {1: Cards.battle(2, 2000, "RED"), 3: blue},  # RED in crush path (zone 2)
		},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4, 1]}
	var s := States.make_session(state, input)

	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(2)
	assert_bool(p0.zone_has_cards(1)).is_false()  # RED crushed during movement
	# Only 1 color remained post-crush, yet Monster X plays from discard.
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(1)  # crushed RED only
	assert_bool(state.players[1].zone_has_cards(1)).is_false()  # lowest rank destroyed


func test_ebp03_067_invasion_discard_with_one_color_stays_in_discard() -> void:
	# Condition still enforced at discard time: only one color in zones.
	var card := Real.instance("EBP03-067")
	var state := States.make_state({
		"p0": {
			"hand": [card],
			"monster_zone": 1,
			"zone_cards": {3: Cards.battle(2, 2000, "RED")},
		},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)  # Monster X stays
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


func test_ebp03_067_invasion_discard_plays_when_no_color_crushed() -> void:
	# Deferred invasion path, positive case with no crush interference.
	var card := Real.instance("EBP03-067")
	var blue := Cards.battle(2, 2000, "BLUE")
	blue["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"p0": {
			"hand": [card],
			"monster_zone": 1,
			"zone_cards": {3: Cards.battle(2, 2000, "RED"), 4: blue},
		},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [6, 1]}
	var s := States.make_session(state, input)

	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(2)
	assert_str(str(p0.get_zone_top_card(6).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(1)).is_false()


# --- EBP03-068: Godzilla Flies — own-turn invade lock; moves rank III+ monster zone 3 → 8 ---


func test_ebp03_068_blocks_own_invasion_only_on_own_turn() -> void:
	var card := Real.instance("EBP03-068")
	var state := States.make_state({"p0": {"strategy_zones": [card]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.is_own_invasion_blocked(0)).is_true()
	state.current_player_id = 1
	assert_bool(handler.is_own_invasion_blocked(0)).is_false()


func test_ebp03_068_enter_moves_monster_from_3_to_8_crushing_only_zone_8() -> void:
	var card := Real.instance("EBP03-068")
	var state := States.make_state({"p0": {
		"current_monster": Cards.monster(3, 20000, [CardEnums.CardTrait.GODZILLA], "R3-MON"),
		"monster_zone": 3,
		"zone_cards": {7: Cards.battle(4, 3000, "Z8"), 4: Cards.battle(4, 3000, "Z5")},
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(8)
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("Z8")
	# Zones 4-7 are spared by this movement.
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal("Z5")


func test_ebp03_068_enter_silent_when_not_in_zone_3_or_below_rank_3() -> void:
	# Monster not in zone 3.
	var card := Real.instance("EBP03-068")
	var state := States.make_state({"p0": {
		"current_monster": Cards.monster(3, 20000, [], "R3-MON"), "monster_zone": 2,
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[0].monster_zone).is_equal(2)

	# Monster below rank III.
	var card2 := Real.instance("EBP03-068", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": Cards.monster(2, 9000, [], "R2-MON"), "monster_zone": 3,
	}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[0].monster_zone).is_equal(3)


# --- EBP03-069: Space Beam — opp discards to 4; Mechagodzilla in zone 8 → destroy all ≤5 ---


func test_ebp03_069_discards_to_4_and_destroys_rank5_with_mechagodzilla_in_zone_8() -> void:
	var card := Real.instance("EBP03-069")
	var mecha := Cards.battle(5, 4000, "MECHA", [CardEnums.CardTrait.MECHAGODZILLA])
	var opp_hand: Array = []
	for i in range(6):
		opp_hand.append(Cards.battle(2, 2000, "OH-%d" % i))
	var state := States.make_state({
		"p0": {"zone_cards": {7: mecha}},
		"p1": {"hand": opp_hand, "zone_cards": {1: Cards.battle(4, 3000, "OPP-R4"), 3: Cards.battle(6, 3000, "OPP-R6")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_int(p1.hand.size()).is_equal(4)
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP-R6")


func test_ebp03_069_only_discards_without_mechagodzilla_in_zone_8() -> void:
	var card := Real.instance("EBP03-069")
	var opp_hand: Array = []
	for i in range(6):
		opp_hand.append(Cards.battle(2, 2000, "OH-%d" % i))
	var state := States.make_state({
		"p0": {"zone_cards": {7: Cards.battle(5, 4000, "PLAIN")}},
		"p1": {"hand": opp_hand, "zone_cards": {1: Cards.battle(4, 3000, "OPP-R4")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-071: Godzilla's Skeleton — look top 4, keep/discard, draw 2 ---


func test_ebp03_071_arranges_top_4_discards_rest_and_draws_2() -> void:
	var card := Real.instance("EBP03-071")
	var a := Cards.battle(1, 2000, "A")
	var b := Cards.battle(2, 2000, "B")
	var c := Cards.battle(3, 2000, "C")
	var d := Cards.battle(4, 2000, "D")
	var e := Cards.battle(5, 2000, "E")
	var state := States.make_state({"p0": {"main_deck": [a, b, c, d, e]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"arrange_deck": [{"keep": [b], "discard": [a, c, d]}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(2)
	assert_str(str(p0.hand[0].get("id"))).is_equal("B")
	assert_str(str(p0.hand[1].get("id"))).is_equal("E")
	assert_int(p0.main_deck.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(3)


func test_ebp03_071_empty_deck_still_draws_2_via_reshuffle() -> void:
	var card := Real.instance("EBP03-071")
	var state := States.make_state({})
	var p0 := state.players[0]
	p0.discard_pile.append_array([Cards.battle(1, 2000, "X"), Cards.battle(2, 2000, "Y"), Cards.battle(3, 2000, "Z")])
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(p0.hand.size()).is_equal(2)
	assert_int(p0.main_deck.size()).is_equal(1)
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_int(input.count_calls("arrange_deck")).is_equal(0)


# --- EBP03-073: All-Weapon Attack — mill 3; destroy zones matching ranks; retreat if monster matches ---


func test_ebp03_073_destroys_matching_zones_and_retreats_opponent_monster() -> void:
	var card := Real.instance("EBP03-073")
	var state := States.make_state({
		"p0": {"main_deck": [Cards.battle(2, 2000, "M-R2"), Cards.battle(5, 2000, "M-R5A"),
			Cards.battle(5, 2000, "M-R5B"), Cards.battle(1, 2000, "BELOW")]},
		"p1": {"monster_zone": 5, "zone_cards": {
			1: Cards.battle(3, 3000, "OPP-Z2"),
			4: Cards.battle(3, 3000, "OPP-Z5"),
			6: Cards.battle(3, 3000, "OPP-Z7"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}  # destroy first, then retreat
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	var p1 := state.players[1]
	assert_int(p0.discard_pile.size()).is_equal(3)
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("BELOW")
	assert_bool(p1.zone_has_cards(1)).is_false()   # zone 2 matched revealed rank 2
	assert_bool(p1.zone_has_cards(4)).is_false()   # zone 5 matched revealed rank 5
	assert_str(str(p1.get_zone_top_card(6).get("id"))).is_equal("OPP-Z7")
	assert_int(p1.monster_zone).is_equal(4)        # monster was in matched zone 5


func test_ebp03_073_mill_without_matches_changes_nothing_else() -> void:
	var card := Real.instance("EBP03-073")
	var state := States.make_state({
		"p0": {"main_deck": [Cards.battle(8, 2000, "M-R8A"), Cards.battle(8, 2000, "M-R8B"),
			Cards.battle(8, 2000, "M-R8C")]},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP-Z2")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(state.players[1].monster_zone).is_equal(1)
	assert_int(input.count_calls("choose_option")).is_equal(0)


# --- EBP03-074: A Journey of 130 Million Years — play next-rank trait-sharing monster ---


func test_ebp03_074_plays_next_rank_monster_sharing_a_trait() -> void:
	var card := Real.instance("EBP03-074")
	var cur := Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "M2")
	var wrong_trait := Cards.monster(3, 11000, [CardEnums.CardTrait.MOTHRA], "M3-MOTHRA")
	var next := Cards.monster(3, 11000, [CardEnums.CardTrait.GODZILLA], "M3-GOJI")
	var state := States.make_state({"p0": {
		"current_monster": cur, "monster_deck": [wrong_trait, next],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.current_monster.get("id"))).is_equal("M3-GOJI")
	assert_str(str(p0.monster_stack[0].get("id"))).is_equal("M2")
	assert_int(p0.monster_deck.size()).is_equal(1)
	assert_int(p0.rage).is_equal(0)


func test_ebp03_074_silent_above_rank_3_or_without_match() -> void:
	# Rank IV monster: too high.
	var card := Real.instance("EBP03-074")
	var state := States.make_state({"p0": {
		"current_monster": Cards.monster(4, 30000, [CardEnums.CardTrait.GODZILLA], "M4"),
		"monster_deck": [Cards.monster(5, 40000, [CardEnums.CardTrait.GODZILLA], "M5")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_str(str(state.players[0].current_monster.get("id"))).is_equal("M4")

	# No next-rank monster sharing a trait.
	var card2 := Real.instance("EBP03-074", 1)
	var state2 := States.make_state({"p0": {
		"current_monster": Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "M2"),
		"monster_deck": [Cards.monster(3, 11000, [CardEnums.CardTrait.MOTHRA], "M3-MOTHRA")],
	}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_str(str(state2.players[0].current_monster.get("id"))).is_equal("M2")
	assert_int(state2.players[0].monster_deck.size()).is_equal(1)


# --- EBP03-075: Yakusugi — Base; own counter start: evolve a rank ≤4 Evolution card ---


func test_ebp03_075_is_a_base_strategy() -> void:
	var card := Real.instance("EBP03-075")
	var state := States.make_state({})
	var s := _session(state)
	assert_bool(s["effect_handler"].is_base_strategy(card)).is_true()
	assert_bool(s["effect_handler"].is_base_strategy(Cards.strategy(2, "PLAIN"))).is_false()


func test_ebp03_075_counter_start_evolves_chosen_low_rank_card() -> void:
	var card := Real.instance("EBP03-075")
	var larva := Real.instance("EBP03-044")   # rank 3, Evolution7 <Mothra>
	var imago := Real.instance("EBP03-045")   # rank 4 Mothra battle
	var state := States.make_state({"p0": {
		"strategy_zones": [card],
		"zone_cards": {2: larva, 4: Cards.battle(5, 3000, "NO-EVO")},
		"main_deck": [Cards.battle(2, 2000, "FILLER"), imago],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2], "search_cards": [{"id": imago.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(imago.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# Only the Evolution card of rank <= 4 was offered.
	assert_that(input.calls[0]["valid"]).is_equal([2])


func test_ebp03_075_silent_on_opponent_turn() -> void:
	var card := Real.instance("EBP03-075")
	var larva := Real.instance("EBP03-044")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"strategy_zones": [card], "zone_cards": {2: larva}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP03-077: Rebirth of Mothra 3 — return a monster from discard (rank ≤2, or any w/ 5 under) ---


func test_ebp03_077_returns_rank2_monster_directly_when_only_option() -> void:
	var card := Real.instance("EBP03-077")
	var m2 := Cards.monster(2, 9000, [], "M2")
	var m4 := Cards.monster(4, 30000, [], "M4")
	var state := States.make_state({})
	state.players[0].discard_pile.append_array([m2, m4])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "M2"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("M2")
	# No 5-card monster stack: the choice prompt never appeared, and the
	# search pool was rank-filtered.
	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp03_077_with_5_under_can_choose_any_monster() -> void:
	var card := Real.instance("EBP03-077")
	var m2 := Cards.monster(2, 9000, [], "M2")
	var m4 := Cards.monster(4, 30000, [], "M4")
	var state := States.make_state({})
	var p0 := state.players[0]
	p0.discard_pile.append_array([m2, m4])
	for i in range(5):
		p0.monster_stack.append(Cards.monster(1, 4000, [], "U-%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1], "search_cards": [{"id": "M4"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("M4")
	assert_int(input.count_calls("choose_option")).is_equal(1)


func test_ebp03_077_silent_without_monsters_in_discard() -> void:
	var card := Real.instance("EBP03-077")
	var state := States.make_state({})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "BTL"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(0)


# --- EBP03-078: Megalon and Gigan — destroy 1 leftmost + 1 rightmost of 3+ opp battle cards ---


func test_ebp03_078_destroys_rightmost_and_leftmost_battle_cards() -> void:
	# Columns (your perspective): idx4 = leftmost col, idx2 = middle, idx0 = rightmost col.
	var card := Real.instance("EBP03-078")
	var state := States.make_state({
		"p1": {"monster_zone": 6, "zone_cards": {
			4: Cards.battle(3, 3000, "LEFT"),
			2: Cards.battle(3, 3000, "MID"),
			0: Cards.battle(3, 3000, "RIGHT"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0, 4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_bool(p1.zone_has_cards(4)).is_false()
	assert_str(str(p1.get_zone_top_card(2).get("id"))).is_equal("MID")
	# First prompt offered the rightmost column, second the leftmost.
	assert_that(input.calls[0]["valid"]).is_equal([0])
	assert_that(input.calls[1]["valid"]).is_equal([4])


func test_ebp03_078_silent_with_fewer_than_3_opponent_battle_cards() -> void:
	var card := Real.instance("EBP03-078")
	var state := States.make_state({
		"p1": {"zone_cards": {4: Cards.battle(3, 3000, "LEFT"), 1: Cards.battle(3, 3000, "RIGHT")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(4)).is_true()
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- EBP03-079: Godzilla Captured! — set opp rage to 0 ---


func test_ebp03_079_sets_opponent_rage_to_0() -> void:
	var card := Real.instance("EBP03-079")
	var state := States.make_state({"p1": {"rage": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(0)

	# Already at 0: harmless.
	var card2 := Real.instance("EBP03-079", 1)
	var state2 := States.make_state({})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(0)


# --- EBP03-080: Odo Island — Base; own counter start: play a Godzilla battle from hand ---


func test_ebp03_080_is_a_base_strategy() -> void:
	var card := Real.instance("EBP03-080")
	var state := States.make_state({})
	var s := _session(state)
	assert_bool(s["effect_handler"].is_base_strategy(card)).is_true()


func test_ebp03_080_counter_start_plays_godzilla_battle_from_hand() -> void:
	var card := Real.instance("EBP03-080")
	var goji := Cards.battle(6, 5000, "GOJI", [CardEnums.CardTrait.GODZILLA])
	var state := States.make_state({"p0": {
		"strategy_zones": [card],
		"hand": [goji, Cards.battle(3, 2000, "PLAIN")],
	}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("GOJI")
	assert_int(p0.hand.size()).is_equal(1)
	assert_int(p0.discard_pile.size()).is_equal(0)
	# Only the Godzilla battle card was offered.
	assert_that(input.calls[0]["valid"]).is_equal([0])


func test_ebp03_080_silent_on_opponent_turn_and_skippable() -> void:
	# Opponent's turn: no prompt.
	var card := Real.instance("EBP03-080")
	var goji := Cards.battle(6, 5000, "GOJI", [CardEnums.CardTrait.GODZILLA])
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"strategy_zones": [card], "hand": [goji]},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Skipping keeps the hand intact.
	var card2 := Real.instance("EBP03-080", 1)
	var state2 := States.make_state({"p0": {
		"strategy_zones": [card2],
		"hand": [Cards.battle(6, 5000, "GOJI2", [CardEnums.CardTrait.GODZILLA])],
	}})
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state2.players[0].hand.size()).is_equal(1)
	assert_bool(state2.players[0].zone_has_cards(2)).is_false()
