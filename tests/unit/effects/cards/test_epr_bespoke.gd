extends GdUnitTestSuite

## Tier C bespoke tests for EPR promo cards (see classification.md).
## Currently EPR-016 — the other EPR effects live in the destroy_target and
## cp_modifiers clusters.

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
