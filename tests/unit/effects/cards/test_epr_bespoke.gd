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
