extends GdUnitTestSuite

## Tier C bespoke tests for EBP01 cards 045-080 (see classification.md).
## One-of-a-kind effects driven through the real trigger-dispatch seam.
## The 004-044 half lives in test_ebp01_bespoke_a.gd.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


# --- EBP01-045: Meganula — enter in opp monster column w/ 2+ battle cards:
# --- reduce opponent rage 1 ---


func test_ebp01_045_enter_reduces_rage_in_monster_column_with_2_battle_cards() -> void:
	var card := Real.instance("EBP01-045")
	# Zone 3 (idx 2) faces opponent zones 3/8 — opponent monster at 3 matches.
	var state := States.make_state({
		"p0": {"zone_cards": {2: card, 4: Cards.battle(1, 2000, "B2")}},
		"p1": {"monster_zone": 3, "rage": 2},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(1)


func test_ebp01_045_silent_outside_column_or_with_single_battle_card() -> void:
	# Wrong column: zone 3 faces opponent zones 3/8, monster sits at 5.
	var card := Real.instance("EBP01-045")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card, 4: Cards.battle(1, 2000, "B2")}},
		"p1": {"monster_zone": 5, "rage": 2},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(2)

	# In column, but it's the only battle card on the board.
	var card2 := Real.instance("EBP01-045", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}, "p1": {"monster_zone": 3, "rage": 2}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(2)


# --- EBP01-048: Biollante Rose Form — main phase: Evolution7 <Biollante> ---


func test_ebp01_048_main_phase_evolves_into_rank_7_biollante() -> void:
	var card := Real.instance("EBP01-048")
	var target := Real.instance("EBP01-058")     # rank 7 Biollante — eligible
	var state := States.make_state({"p0": {
		"zone_cards": {3: card},
		"main_deck": [target, Cards.battle(2, 2000, "NOT-BIO")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# Opponent's turn first: no prompt.
	state.current_player_id = 1
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	state.current_player_id = 0
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].get_zone_stack(3).size()).is_equal(2)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP01-049: Destoroyah Aggregate Form — main phase: Evolution6 ---


func test_ebp01_049_main_phase_evolves_into_rank_6_destoroyah() -> void:
	var card := Real.instance("EBP01-049")
	var target := Real.instance("EBP01-049", 1)  # rank 4 Destoroyah — eligible
	var too_big := Real.instance("EBP01-060")    # rank 8 — over Evolution6
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "main_deck": [target, too_big]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	state.current_player_id = 1
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	state.current_player_id = 0
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].get_zone_stack(1).size()).is_equal(2)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP01-050: Mothra(larva)(1992) — main phase: Evolution7 <Mothra> ---


func test_ebp01_050_main_phase_evolves_into_rank_7_mothra() -> void:
	var card := Real.instance("EBP01-050")
	var target := Real.instance("EBP01-057")     # rank 7 Mothra — eligible
	var decoy := Real.instance("EBP01-021")      # Rodan — wrong trait
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "main_deck": [target, decoy]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	state.current_player_id = 1
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	state.current_player_id = 0
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(2)
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP01-054: Destoroyah Flying Form — Evolution8 + enter-through-evolution
# --- draws 2 then discards 2 ---


func test_ebp01_054_main_phase_evolves_into_rank_8_destoroyah() -> void:
	var card := Real.instance("EBP01-054")
	var target := Real.instance("EBP01-060")     # rank 8 Destoroyah — eligible
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "main_deck": [target]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(2)


func test_ebp01_054_enter_through_evolution_draws_2_then_discards_2() -> void:
	# Evolve EBP01-049 into 054 — the evolution marks it played_through_evolution.
	var aggregate := Real.instance("EBP01-049")
	var card := Real.instance("EBP01-054")
	var state := States.make_state({"p0": {
		"zone_cards": {3: aggregate},
		"main_deck": [card, Cards.battle(1, 2000, "F1"), Cards.battle(1, 2000, "F2")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": card.get("id")}], "choose_hand_discards": [[1, 0]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(2)
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp01_054_enter_without_evolution_does_not_draw() -> void:
	var card := Real.instance("EBP01-054")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2")],
	}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(2)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP01-057: Mothra(imago)(1992) — enter: may swap 2 battle cards;
# --- adjacent rank<=5 cards gain +3000 CP ---


func test_ebp01_057_enter_may_swap_two_battle_cards() -> void:
	var card := Real.instance("EBP01-057")
	var other := Cards.battle(2, 2000, "OTHER")
	var state := States.make_state({"p0": {"zone_cards": {1: card, 3: other}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3, 1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal("OTHER")
	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))

	# Skipping the first pick leaves the board alone (second prompt never shown).
	var card2 := Real.instance("EBP01-057", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {1: card2, 3: Cards.battle(2, 2000, "OTHER2")}}})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_zone": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_str(str(state2.players[0].get_zone_top_card(1).get("id"))).is_equal(str(card2.get("id")))
	assert_int(input2.count_calls("select_zone")).is_equal(1)


func test_ebp01_057_boosts_adjacent_rank_5_or_lower_by_3000() -> void:
	var card := Real.instance("EBP01-057")
	var small := Cards.battle(5, 4000, "SMALL")
	var big := Cards.battle(6, 5000, "BIG")
	var far := Cards.battle(5, 4000, "FAR")
	# Card at zone 4 (idx 3): adjacent zones are idx 2, 4, 6.
	var state := States.make_state({"p0": {"zone_cards": {3: card, 2: small, 4: big, 5: far}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(7000)   # rank 5 adjacent: +3000
	assert_int(handler.get_effective_zone_cp(0, 4)).is_equal(5000)   # rank 6 adjacent: no boost
	assert_int(handler.get_effective_zone_cp(0, 5)).is_equal(4000)   # rank 5 but not adjacent


# --- EBP01-058: Biollante Plant Beast Form — rank -2 with Evolution Biollante
# --- in discard; enter: shuffle discard into deck ---


func test_ebp01_058_rank_minus_2_with_evolution_biollante_and_enter_recycles() -> void:
	var card := Real.instance("EBP01-058")
	var evo := Real.instance("EBP01-048")        # Biollante with <Evolution>
	var state := States.make_state({"p0": {"hand": [card]}})
	state.players[0].discard_pile.append_array([evo, Cards.battle(1, 2000, "JUNK")])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-2)

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(2)


func test_ebp01_058_no_discount_without_evolution_biollante() -> void:
	var card := Real.instance("EBP01-058")
	var state := States.make_state({"p0": {"hand": [card]}})
	# A Biollante card WITHOUT <Evolution> does not qualify.
	state.players[0].discard_pile.append(Real.instance("EBP01-058", 1))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


# --- EBP01-059: Fire Rodan — discarded by opponent effect w/ their monster
# --- in zones 4-8: may play self; +3000 CP in zone 8 ---


func test_ebp01_059_plays_self_when_discarded_by_opponent_effect() -> void:
	var card := Real.instance("EBP01-059")
	var state := States.make_state({"p1": {"monster_zone": 4}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	# Simulate an opponent effect causing the discard (caused_by_opponent gate).
	handler.exec.set_active(1, {"id": "OPP-FX", "name": "Opponent Effect"})

	await handler.trigger_discard_from_hand(0, card)

	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_ebp01_059_silent_when_monster_back_or_not_caused_by_opponent() -> void:
	# Opponent monster in zones 1-3: no play offer.
	var card := Real.instance("EBP01-059")
	var state := States.make_state({"p1": {"monster_zone": 3}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.set_active(1, {"id": "OPP-FX"})
	await handler.trigger_discard_from_hand(0, card)
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Own effect caused the discard: the trigger filter gates it off.
	var card2 := Real.instance("EBP01-059", 1)
	var state2 := States.make_state({"p1": {"monster_zone": 4}})
	state2.players[0].discard_pile.append(card2)
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	handler2.exec.set_active(0, {"id": "MY-FX"})
	await handler2.trigger_discard_from_hand(0, card2)
	assert_int(input2.count_calls("select_zone")).is_equal(0)

	# Rules-based discard (no active effect): matches neither gate value.
	var card3 := Real.instance("EBP01-059", 2)
	var state3 := States.make_state({"p1": {"monster_zone": 4}})
	state3.players[0].discard_pile.append(card3)
	var input3 := ScriptedPlayerInput.new()
	var s3 := States.make_session(state3, input3)
	await s3["effect_handler"].trigger_discard_from_hand(0, card3)
	assert_int(input3.count_calls("select_zone")).is_equal(0)


func test_ebp01_059_gains_3000_cp_in_zone_8() -> void:
	var card := Real.instance("EBP01-059")
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	var s := _session(state)
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 7)).is_equal(9000)

	var card2 := Real.instance("EBP01-059", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}})
	var s2 := _session(state2)
	assert_int(s2["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(6000)


# --- EBP01-060: Destoroyah Perfect Form — enter via evolution: replay a
# --- "Godzilla vs. Destoroyah" strategy from discard ---


func test_ebp01_060_evolution_enter_replays_godzilla_vs_destoroyah_from_discard() -> void:
	var card := Real.instance("EBP01-060")
	card["played_through_evolution"] = true
	var gvd := Real.instance("EBP01-065")  # strategy named "Godzilla vs. Destoroyah"
	var state := States.make_state({
		"p0": {"zone_cards": {4: card}},
		"p1": {"zone_cards": {1: Cards.battle(3, 2000, "BACK"), 6: Cards.battle(3, 2000, "FRONT")}},
	})
	state.players[0].discard_pile.append_array([gvd, Cards.strategy(2, "OTHER-STRAT")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": gvd.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].strategy_zones[0].get("id"))).is_equal(str(gvd.get("id")))
	# The replayed strategy's own enter fired: opponent zones 1-5 destroyed.
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(6)).is_true()
	# Only name+type matched cards were offered.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp01_060_requires_evolution_play_and_free_strategy_room() -> void:
	# Played normally (not through evolution): no search.
	var card := Real.instance("EBP01-060")
	var state := States.make_state({"p0": {"zone_cards": {4: card}}})
	state.players[0].discard_pile.append(Real.instance("EBP01-065"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Through evolution but with 2 strategies already in play: no search.
	var card2 := Real.instance("EBP01-060", 1)
	card2["played_through_evolution"] = true
	var state2 := States.make_state({"p0": {
		"zone_cards": {4: card2},
		"strategy_zones": [Cards.strategy(2, "SA"), Cards.strategy(3, "SB")],
	}})
	state2.players[0].discard_pile.append(Real.instance("EBP01-065", 1))
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(input2.count_calls("search_cards")).is_equal(0)


# --- EBP01-061: Scale Attack — opponent at 5+ rage: reduce by 3 ---


func test_ebp01_061_reduces_rage_3_only_at_5_or_more() -> void:
	var card := Real.instance("EBP01-061")
	var state := States.make_state({"p1": {"rage": 5}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(2)

	# Rage 4: untouched.
	var card2 := Real.instance("EBP01-061", 1)
	var state2 := States.make_state({"p1": {"rage": 4}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(4)


# --- EBP01-063: Guardians Awaken — evolve all rank<=4 Evolution cards ---


func test_ebp01_063_enter_evolves_all_rank_4_evolution_cards_in_chosen_order() -> void:
	var card := Real.instance("EBP01-063")
	var egg := Real.instance("EBP01-044")        # rank 1 Evolution5 Mothra
	var aggregate := Real.instance("EBP01-049")  # rank 4 Evolution6 Destoroyah
	var big := Real.instance("EBP01-054")        # rank 6 — over the cap
	var mothra_t := Real.instance("EBP01-050", 1)
	var dest_t := Real.instance("EBP01-049", 2)
	var state := States.make_state({"p0": {
		"zone_cards": {1: egg, 5: aggregate, 7: big},
		"main_deck": [mothra_t, dest_t],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"choose_option": [0],
		"search_cards": [{"id": mothra_t.get("id")}, {"id": dest_t.get("id")}],
	}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(mothra_t.get("id")))
	assert_int(p0.get_zone_stack(1).size()).is_equal(2)
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal(str(dest_t.get("id")))
	assert_int(p0.get_zone_stack(5).size()).is_equal(2)
	# Rank 6 evolution card: ineligible, untouched.
	assert_int(p0.get_zone_stack(7).size()).is_equal(1)
	# Order was only asked once (the final evolution auto-resolves).
	assert_int(input.count_calls("choose_option")).is_equal(1)


# --- EBP01-064: Godzilla vs. Megaguirus — choose: destroy 1 rank<=4 OR
# --- (w/ 4+ own battle cards) destroy a zone + its adjacents ---


func test_ebp01_064_single_available_option_destroys_rank_4_without_choice() -> void:
	var card := Real.instance("EBP01-064")
	var state := States.make_state({
		"p1": {"zone_cards": {1: Cards.battle(4, 3000, "R4"), 3: Cards.battle(5, 4000, "R5")}},
	})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(3)).is_true()
	# With fewer than 4 own battle cards there is no mode choice.
	assert_int(input.count_calls("choose_option")).is_equal(0)
	# The destroy prompt only offered the rank<=4 target.
	assert_int(input.calls[0]["valid"].size()).is_equal(1)
	assert_bool(3 in input.calls[0]["valid"]).is_false()


func test_ebp01_064_choice_b_destroys_chosen_zone_and_adjacents() -> void:
	var card := Real.instance("EBP01-064")
	var state := States.make_state({
		"p0": {"zone_cards": {
			1: Cards.battle(1, 2000, "M1"), 2: Cards.battle(1, 2000, "M2"),
			4: Cards.battle(1, 2000, "M3"), 5: Cards.battle(1, 2000, "M4"),
		}},
		"p1": {"zone_cards": {
			1: Cards.battle(2, 2000, "SAFE"),
			2: Cards.battle(4, 3000, "A4"),
			3: Cards.battle(5, 4000, "A5"),
			6: Cards.battle(6, 5000, "A6"),
		}},
	})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1], "select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	# Zone 4 (idx 3) + adjacents idx 2, 4, 6 — regardless of rank.
	assert_bool(p1.zone_has_cards(3)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_bool(p1.zone_has_cards(6)).is_false()
	assert_bool(p1.zone_has_cards(1)).is_true()
	assert_int(p1.discard_pile.size()).is_equal(3)
	# Mode choice was presented with both options.
	assert_int(input.calls[0]["options"].size()).is_equal(2)


func test_ebp01_064_no_valid_targets_means_no_prompts() -> void:
	var card := Real.instance("EBP01-064")
	var state := States.make_state({})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP01-066: Godzilla vs. Biollante — counter immunity 40k on opp turn;
# --- +2 rage when discarded from hand by opponent effect ---


func test_ebp01_066_counter_immunity_40000_only_on_opponents_turn() -> void:
	var card := Real.instance("EBP01-066")
	var state := States.make_state({"current_player_id": 1})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_counter_immunity_threshold(0)).is_equal(40000)

	state.current_player_id = 0
	assert_int(handler.get_counter_immunity_threshold(0)).is_equal(0)


func test_ebp01_066_gains_2_rage_when_discarded_by_opponent_effect() -> void:
	var card := Real.instance("EBP01-066")
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.set_active(1, {"id": "OPP-FX", "name": "Opponent Effect"})

	await handler.trigger_discard_from_hand(0, card)

	assert_int(state.players[0].rage).is_equal(2)
	# NOTE: the script declares no caused_by_opponent TRIGGER_FILTERS gate, so
	# it would ALSO fire for self/rules-caused discards, contradicting the card
	# text ("by your opponent's effect"). Reported as a suspected bug; the
	# negative case is intentionally not asserted here.


# --- EBP01-069: Varan — Awakening6 enter: draw 2, discard 2 ---


func test_ebp01_069_enter_with_awakening6_draws_2_then_discards_2() -> void:
	var card := Real.instance("EBP01-069")
	var state := States.make_state({"p0": {
		"monster_zone": 6,
		"zone_cards": {2: card},
		"hand": [Cards.battle(1, 2000, "KEEP")],
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2"), Cards.battle(1, 2000, "D3")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[2, 1]]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("KEEP")
	assert_int(p0.discard_pile.size()).is_equal(2)
	assert_int(p0.main_deck.size()).is_equal(1)

	# Awakening 5: silent.
	var card2 := Real.instance("EBP01-069", 1)
	var state2 := States.make_state({"p0": {
		"monster_zone": 5,
		"zone_cards": {2: card2},
		"hand": [Cards.battle(1, 2000, "K")],
		"main_deck": [Cards.battle(1, 2000, "E1"), Cards.battle(1, 2000, "E2")],
	}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[0].hand.size()).is_equal(1)
	assert_int(state2.players[0].main_deck.size()).is_equal(2)
	assert_int(input2.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP01-070: Baragon(1968) — enter: look at deck top, may discard it ---


func test_ebp01_070_enter_looks_at_top_card_and_may_discard_it() -> void:
	var card := Real.instance("EBP01-070")
	var d1 := Cards.battle(1, 2000, "TOP")
	var d2 := Cards.battle(1, 2000, "NEXT")
	var state := States.make_state({"p0": {"zone_cards": {1: card}, "main_deck": [d1, d2]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"arrange_deck": [{"keep": [], "discard": [d1]}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_str(str(state.players[0].main_deck[0].get("id"))).is_equal("NEXT")
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("TOP")

	# Keeping it puts it back on top.
	var card2 := Real.instance("EBP01-070", 1)
	var k1 := Cards.battle(1, 2000, "KEEP-TOP")
	var state2 := States.make_state({"p0": {"zone_cards": {1: card2}, "main_deck": [k1, Cards.battle(1, 2000, "K2")]}})
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"arrange_deck": [{"keep": [k1], "discard": []}]}
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_str(str(state2.players[0].main_deck[0].get("id"))).is_equal("KEEP-TOP")
	assert_int(state2.players[0].discard_pile.size()).is_equal(0)


# --- EBP01-071: Giant Condor — +5000 CP in opp monster column; destroyed
# --- when opponent rage increases ---


func test_ebp01_071_gains_5000_cp_in_opponent_monster_column() -> void:
	var card := Real.instance("EBP01-071")
	# Zone 3 (idx 2) faces opponent zones 3/8.
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(10000)

	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)


func test_ebp01_071_destroyed_when_opponent_rage_increases() -> void:
	var card := Real.instance("EBP01-071")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.gain_rage(1, 1)

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)

	# Opponent rage DECREASE: survives (direction filter).
	var card2 := Real.instance("EBP01-071", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}, "p1": {"rage": 1}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.reduce_rage(1, 1)
	assert_bool(state2.players[0].zone_has_cards(2)).is_true()


# --- EBP01-073: Godzilla Against Mechagodzilla — unplayable until 8 monsters
# --- discarded; on own invasion may stack a discard monster to zero opp rage ---


func test_ebp01_073_unplayable_until_8_monsters_in_discard() -> void:
	var card := Real.instance("EBP01-073")
	var state := States.make_state({"p0": {"hand": [card]}})
	for i in range(7):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_bool(handler.can_card_be_played(0, card)).is_false()

	state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM7"))
	assert_bool(handler.can_card_be_played(0, card)).is_true()


func test_ebp01_073_invasion_may_stack_discard_monster_to_zero_opponent_rage() -> void:
	var card := Real.instance("EBP01-073")
	var mon := Cards.monster(2, 9000, [], "DM")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}, "p1": {"rage": 3}})
	state.players[0].discard_pile.append_array([mon, Cards.battle(1, 2000, "B")])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DM"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_invasion_observed(0, 2, 3)

	assert_int(state.players[0].get_zone_stack(1).size()).is_equal(2)
	assert_int(state.players[1].rage).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	# Only monsters were offered from the discard pile.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_ebp01_073_silent_with_monster_already_under_and_skippable() -> void:
	# A monster already stacked under: no prompt.
	var card := Real.instance("EBP01-073")
	var state := States.make_state({"p0": {"zone_cards": {1: card}}, "p1": {"rage": 3}})
	state.players[0].zones[1].append(Cards.monster(1, 5000, [], "UNDER"))
	state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_invasion_observed(0, 2, 3)
	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_int(state.players[1].rage).is_equal(3)

	# Declining the search leaves rage alone.
	var card2 := Real.instance("EBP01-073", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {1: card2}}, "p1": {"rage": 3}})
	state2.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DM2"))
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"search_cards": [{}]}
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_invasion_observed(0, 2, 3)
	assert_int(state2.players[1].rage).is_equal(3)
	assert_int(state2.players[0].get_zone_stack(1).size()).is_equal(1)


# --- EBP01-075: Godzilla, King of the Monsters — +3000 CP per rage; protected
# --- in zones 1-5 at 3+ rage vs opponent effects; Awakening8 rank -4 ---


func test_ebp01_075_cp_scales_with_rage() -> void:
	var card := Real.instance("EBP01-075")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)

	state.players[0].rage = 2
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(11000)


func test_ebp01_075_awakening8_reduces_play_rank_by_4() -> void:
	var card := Real.instance("EBP01-075")
	var state := States.make_state({"p0": {"hand": [card], "monster_zone": 8}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-4)

	state.players[0].monster_zone = 7
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_ebp01_075_indestructible_by_opponent_effects_in_zones_1_5_with_3_rage() -> void:
	var card := Real.instance("EBP01-075")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "rage": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.set_active(1, {"id": "OPP-FX"})

	assert_bool(handler.can_destroy_card(state.players[0], card)).is_false()
	await handler.destroy_zones(state.players[0], [2])
	assert_bool(state.players[0].zone_has_cards(2)).is_true()

	# Below 3 rage: destroyable.
	state.players[0].rage = 2
	await handler.destroy_zones(state.players[0], [2])
	assert_bool(state.players[0].zone_has_cards(2)).is_false()

	# Own effect as the cause: protection does not apply.
	var card2 := Real.instance("EBP01-075", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}, "rage": 3}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	handler2.exec.set_active(0, {"id": "MY-FX"})
	await handler2.destroy_zones(state2.players[0], [2])
	assert_bool(state2.players[0].zone_has_cards(2)).is_false()

	# Zones 6-8: not protected even with 3 rage.
	var card3 := Real.instance("EBP01-075", 2)
	var state3 := States.make_state({"p0": {"zone_cards": {6: card3}, "rage": 3}})
	var s3 := _session(state3)
	var handler3: EffectHandler = s3["effect_handler"]
	handler3.exec.set_active(1, {"id": "OPP-FX"})
	await handler3.destroy_zones(state3.players[0], [6])
	assert_bool(state3.players[0].zone_has_cards(6)).is_false()


# --- EBP01-077: Oxygen Destroyer — opp rage<=2: move their monster as
# --- though countered (8→3 / 7→4 / 6→5, no rank up) ---


func test_ebp01_077_moves_opponent_monster_as_countered_at_rage_2_or_less() -> void:
	var card := Real.instance("EBP01-077")
	var opp_monster := Cards.monster(2, 9000, [], "OPP-MON")
	var state := States.make_state({"p1": {"monster_zone": 8, "rage": 2, "current_monster": opp_monster}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(3)
	# No rank-up: the same monster is still in play.
	assert_str(str(state.players[1].current_monster.get("id"))).is_equal("OPP-MON")

	# Rage 3: untouched.
	var card2 := Real.instance("EBP01-077", 1)
	var state2 := States.make_state({"p1": {"monster_zone": 7, "rage": 3}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(7)

	# Zones 1-5 don't move when countered.
	var card3 := Real.instance("EBP01-077", 2)
	var state3 := States.make_state({"p1": {"monster_zone": 4}})
	state3.players[0].strategy_zones[0] = card3
	var s3 := _session(state3)
	var handler3: EffectHandler = s3["effect_handler"]
	await handler3.trigger_enter(0, card3)
	assert_int(state3.players[1].monster_zone).is_equal(4)


# --- EBP01-078: Godzilla Attacks — advance own monster to zone 6 ---


func test_ebp01_078_enter_advances_monster_to_zone_6_crushing_along_the_way() -> void:
	var card := Real.instance("EBP01-078")
	var state := States.make_state({"p0": {"monster_zone": 3, "zone_cards": {4: Cards.battle(2, 2000, "CRUSHED")}}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(6)
	# The battle card in zone 5 was crushed on the way through (rule 11.3).
	assert_bool(state.players[0].zone_has_cards(4)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)

	# Already past zone 6: stays.
	var card2 := Real.instance("EBP01-078", 1)
	var state2 := States.make_state({"p0": {"monster_zone": 7}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[0].monster_zone).is_equal(7)


# --- EBP01-079: Gravity Beam — opponent discards to 3 ---


func test_ebp01_079_enter_discards_opponent_down_to_3() -> void:
	var card := Real.instance("EBP01-079")
	var hand: Array = []
	for i in range(5):
		hand.append(Cards.battle(1, 2000, "H%d" % i))
	var state := States.make_state({"p1": {"hand": hand}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[4, 3]]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].hand.size()).is_equal(3)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)

	# Already at 3 or fewer: no prompt.
	var card2 := Real.instance("EBP01-079", 1)
	var state2 := States.make_state({"p1": {"hand": [Cards.battle(1, 2000, "K1"), Cards.battle(1, 2000, "K2")]}})
	state2.players[0].strategy_zones[0] = card2
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].hand.size()).is_equal(2)
	assert_int(input2.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP01-080: Godzilla and its son on Monster Island — rank -2 if opponent
# --- has a strategy; protects own rank<=5 cards in zones 1-5 from opp effects ---


func test_ebp01_080_play_rank_minus_2_when_opponent_has_a_strategy() -> void:
	var card := Real.instance("EBP01-080")
	var state := States.make_state({"p0": {"hand": [card]}, "p1": {"strategy_zones": [Cards.strategy(2, "OPP-S")]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-2)

	state.players[1].strategy_zones[0] = {}
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_ebp01_080_protects_rank_5_cards_in_zones_1_5_from_opponent_effects() -> void:
	var strat := Real.instance("EBP01-080")
	var protected_card := Cards.battle(5, 4000, "SAFE")
	var big := Cards.battle(6, 5000, "BIG")
	var front := Cards.battle(5, 4000, "FRONT")
	var state := States.make_state({"p0": {"zone_cards": {2: protected_card, 3: big, 6: front}}})
	state.players[0].strategy_zones[0] = strat
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.set_active(1, {"id": "OPP-FX"})

	assert_bool(handler.can_destroy_card(state.players[0], protected_card)).is_false()
	await handler.destroy_zones(state.players[0], [2, 3, 6])

	assert_bool(state.players[0].zone_has_cards(2)).is_true()    # rank 5, zone 3: protected
	assert_bool(state.players[0].zone_has_cards(3)).is_false()   # rank 6: not protected
	assert_bool(state.players[0].zone_has_cards(6)).is_false()   # zone 7: outside 1-5

	# Own effect as the cause: no protection.
	handler.exec.set_active(0, {"id": "MY-FX"})
	await handler.destroy_zones(state.players[0], [2])
	assert_bool(state.players[0].zone_has_cards(2)).is_false()

	# Not a <Base> strategy (explicit override).
	assert_bool(handler.is_base_strategy(strat)).is_false()
