extends GdUnitTestSuite

## Tier C bespoke tests for EPR promo cards (see classification.md).
## EPR-016 through EPR-020 — the other EPR effects live in the destroy_target
## and cp_modifiers clusters.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


# --- EPR-016: KIJU Type 0 -G BREAKER- — own counter phase: stack a Mech/
# --- Weapon/RIDE battle card from hand; +5000 CP while stacked; self-destroy
# --- at the start of the end phase if loaded ---


func test_epr_016_counter_phase_stacks_hand_card_for_5000_cp_then_end_phase_destroys() -> void:
	var card := Real.instance("EPR-016")
	var weapon := Cards.battle(2, 2000, "HAND-WEAPON", [CardEnums.CardTrait.WEAPON])
	var plain := Cards.battle(2, 2000, "HAND-PLAIN")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "hand": [weapon, plain]}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	# Only the Weapon card was offered; it moved hand -> under this card,
	# NOT via the discard pile (no discard triggers).
	assert_array(input.calls[0]["valid"]).contains_exactly([0])
	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000 + 5000)

	# Start of the same turn's end phase: the loaded card destroys itself,
	# whole stack to the discard pile.
	state.current_phase = CardEnums.GamePhase.END
	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


func test_epr_016_skip_keeps_card_and_no_bonus_and_survives_end_phase() -> void:
	var card := Real.instance("EPR-016")
	var mech := Cards.battle(2, 2000, "HAND-MECH", [CardEnums.CardTrait.MECH])
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "hand": [mech]}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000)

	# Nothing under it: survives the end phase.
	state.current_phase = CardEnums.GamePhase.END
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_bool(state.players[0].zone_has_cards(2)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_epr_016_unused_copy_stays_out_of_end_phase_standby() -> void:
	# Two copies fielded, one eligible hand card: at counter start both
	# copies trigger (order prompt), the first tucks the card, the second
	# finds none. At end-phase start only the copy that USED its ability has
	# a trigger — no second 10.6.3.1 order-choice prompt fires.
	var used := Real.instance("EPR-016")
	var unused := Real.instance("EPR-016", 1)
	var weapon := Cards.battle(2, 2000, "HAND-W", [CardEnums.CardTrait.WEAPON])
	var state := States.make_state({"p0": {"zone_cards": {2: used, 5: unused}, "hand": [weapon]}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	var counter_order_prompts := input.count_calls("choose_option")

	state.current_phase = CardEnums.GamePhase.END
	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(input.count_calls("choose_option")) \
		.override_failure_message("unused copy must not enter the end-phase standby order-choice prompt") \
		.is_equal(counter_order_prompts)
	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_bool(state.players[0].zone_has_cards(5)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


func test_epr_016_card_tucked_by_external_effect_does_not_arm_destroy() -> void:
	# Future-proofing: a card under this copy that its OWN ability did not
	# tuck (e.g. some other effect places it there) keeps the printed CP
	# bonus but must NOT create the end-phase destroy trigger.
	var card := Real.instance("EPR-016")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].zones[2].append(Cards.battle(2, 2000, "EXT-UNDER", [CardEnums.CardTrait.WEAPON]))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000 + 5000)

	state.current_phase = CardEnums.GamePhase.END
	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_bool(state.players[0].zone_has_cards(2)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_epr_016_gated_to_own_counter_phase_and_needs_eligible_hand_card() -> void:
	var card := Real.instance("EPR-016")
	var weapon := Cards.battle(2, 2000, "HAND-WEAPON2", [CardEnums.CardTrait.WEAPON])
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "hand": [weapon]}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# Opponent's counter phase: filter blocks it.
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.COUNTER
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Own counter phase but no Mech/Weapon/RIDE battle card in hand: no prompt.
	state.current_player_id = 0
	state.players[0].hand.clear()
	state.players[0].hand.append(Cards.battle(2, 2000, "HAND-PLAIN2"))
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)


# --- EPR-017: Godzilla(GODZILLA THE RIDE: GREAT CLASH) — enter: place 1
# --- RIDE card from the discard pile under the monster (mandatory) ---


func test_epr_017_enter_places_ride_card_from_discard_under_monster() -> void:
	var card := Real.instance("EPR-017")
	var ride := Cards.battle(2, 2000, "DISC-RIDE", [CardEnums.CardTrait.GODZILLA_THE_RIDE])
	var plain := Cards.battle(2, 2000, "DISC-PLAIN")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append(plain)
	state.players[0].discard_pile.append(ride)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": ride["id"]}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	# Only the RIDE card was offered, and the pick is mandatory (no skip).
	assert_int(input.count_calls("search_cards")).is_equal(1)
	var offered: Array = input.calls[0]["matching"]
	assert_int(offered.size()).is_equal(1)
	assert_str(str(offered[0]["id"])).is_equal(ride["id"])
	assert_int(state.players[0].monster_stack.size()).is_equal(1)
	assert_str(str(state.players[0].monster_stack[0]["id"])).is_equal(ride["id"])
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_str(str(state.players[0].discard_pile[0]["id"])).is_equal(plain["id"])


func test_epr_017_enter_with_no_ride_card_in_discard_does_nothing() -> void:
	var card := Real.instance("EPR-017")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "DISC-PLAIN2"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_stack.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


# --- EPR-018: GODZILLA THE RIDE: GREAT CLASH — discard 1 from hand; if you
# --- do, search the deck for a Mech/Weapon/RIDE battle card to hand ---


func test_epr_018_discards_then_searches_deck_for_mech_weapon_ride_battle() -> void:
	var card := Real.instance("EPR-018")
	var hand_a := Cards.battle(2, 2000, "HAND-A")
	var hand_b := Cards.strategy(2, "HAND-B")
	var mech := Cards.battle(3, 3000, "DECK-MECH", [CardEnums.CardTrait.MECH])
	var ride_strat := Cards.strategy(3, "DECK-RIDE-STRAT")
	ride_strat["traits"] = [CardEnums.CardTrait.GODZILLA_THE_RIDE]
	var plain := Cards.battle(3, 3000, "DECK-PLAIN")
	var state := States.make_state({
		"p0": {"strategy_zones": [card], "hand": [hand_a, hand_b], "main_deck": [plain, ride_strat, mech]},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1], "search_cards": [{"id": mech["id"]}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	# Any hand card is a valid discard.
	assert_array(input.calls[0]["valid"]).contains_exactly([0, 1])
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_str(str(state.players[0].discard_pile[0]["id"])).is_equal(hand_b["id"])
	# Only the Mech battle card matched (RIDE strategy is not a battle card).
	var offered: Array = input.calls[1]["matching"]
	assert_int(offered.size()).is_equal(1)
	assert_str(str(offered[0]["id"])).is_equal(mech["id"])
	assert_int(state.players[0].hand.size()).is_equal(2)
	assert_str(str(state.players[0].hand[1]["id"])).is_equal(mech["id"])
	assert_int(state.players[0].main_deck.size()).is_equal(2)


func test_epr_018_with_empty_hand_does_not_search() -> void:
	var card := Real.instance("EPR-018")
	var mech := Cards.battle(3, 3000, "DECK-MECH2", [CardEnums.CardTrait.MECH])
	var state := States.make_state({"p0": {"strategy_zones": [card], "main_deck": [mech]}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(1)


# --- EPR-019: Gravity Beam — rank -3 from hand with a Fest + King Ghidorah
# --- battle card in play; opponent discards down to 3 ---


func test_epr_019_rank_reduced_by_3_only_with_fest_king_ghidorah_battle_card(traits: Array, expected_mod: int,
		test_parameters := [
			[[CardEnums.CardTrait.FEST, CardEnums.CardTrait.KING_GHIDORAH], -3],
			[[CardEnums.CardTrait.FEST], 0],
			[[CardEnums.CardTrait.KING_GHIDORAH], 0],
		]) -> void:
	var card := Real.instance("EPR-019")
	var zone_card := Cards.battle(4, 4000, "ZONE-GHIDORAH", traits)
	var state := States.make_state({"p0": {"zone_cards": {3: zone_card}, "hand": [card]}})
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_play_rank_modifier(0, card)) \
		.override_failure_message("EPR-019: traits=%s" % [traits]).is_equal(expected_mod)


func test_epr_019_enter_opponent_discards_down_to_3() -> void:
	var card := Real.instance("EPR-019")
	var opp_hand: Array = []
	for i in range(5):
		opp_hand.append(Cards.battle(2, 3000, "OPP-HAND-%d" % i))
	var state := States.make_state({"p0": {"strategy_zones": [card]}, "p1": {"hand": opp_hand}})
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(3)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)


func test_epr_019_enter_with_3_or_fewer_opponent_cards_discards_nothing() -> void:
	var card := Real.instance("EPR-019")
	var state := States.make_state({
		"p0": {"strategy_zones": [card]},
		"p1": {"hand": [Cards.battle(2, 3000, "OPP-ONLY-0"), Cards.battle(2, 3000, "OPP-ONLY-1")]},
	})
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(2)
	assert_int(state.players[1].discard_pile.size()).is_equal(0)


# --- EPR-020: Godzilla(2003) — hand battle discard reduces opp rage 1;
# --- own turn: opp rage reaching 0 gains 2 rage (not if already 0) ---


func _epr_020_state(current_pid: int, opp_rage: int) -> GameState:
	return States.make_state({
		"current_player_id": current_pid,
		"p0": {"current_monster": Real.instance("EPR-020")},
		"p1": {"rage": opp_rage},
	})


func test_epr_020_hand_battle_discard_reduces_opponent_rage_and_gains_2_when_it_hits_0() -> void:
	var state := _epr_020_state(0, 1)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_hand_card_discarded(0, Cards.battle(2, 3000, "DISCARDED-BTL"))

	assert_int(state.players[1].rage).is_equal(0)
	assert_int(state.players[0].rage).is_equal(2)


func test_epr_020_hand_battle_discard_with_opponent_rage_above_1_gains_nothing() -> void:
	var state := _epr_020_state(0, 2)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_hand_card_discarded(0, Cards.battle(2, 3000, "DISCARDED-BTL2"))

	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].rage).is_equal(0)


func test_epr_020_ignores_non_battle_hand_discards() -> void:
	var state := _epr_020_state(0, 1)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_hand_card_discarded(0, Cards.strategy(2, "DISCARDED-STR"))

	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].rage).is_equal(0)


func test_epr_020_opponent_rage_to_0_gains_2_only_on_own_turn(current_pid: int, expected_own_rage: int,
		test_parameters := [
			[0, 2],
			[1, 0],
		]) -> void:
	var state := _epr_020_state(current_pid, 1)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.reduce_rage(1, 1)

	assert_int(state.players[1].rage).is_equal(0)
	assert_int(state.players[0].rage) \
		.override_failure_message("EPR-020: current_pid=%d" % current_pid).is_equal(expected_own_rage)


func test_epr_020_opponent_rage_already_0_does_not_fire() -> void:
	var state := _epr_020_state(0, 0)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	# reduce_rage on a 0-rage player is a no-op (no rage_changed dispatch).
	await handler.reduce_rage(1, 1)
	# A rage increase must not fire either (direction filter).
	await handler.gain_rage(1, 1)

	assert_int(state.players[0].rage).is_equal(0)
