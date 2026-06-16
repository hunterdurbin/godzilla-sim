extends GdUnitTestSuite

## Tier C bespoke tests for EBP04 cards 050-089 + T01 — one-of-a-kind effects
## driven through the real trigger-dispatch seam. See classification.md.
## Part A (001-049) lives in test_ebp04_bespoke_a.gd.

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


# --- EBP04-050: own invasion + zone 8 → draw/discard or discard for rage -1 ---


func test_ebp04_050_choice_a_draws_then_discards() -> void:
	var card := Real.instance("EBP04-050")
	var state := States.make_state({"p0": {
		"zone_cards": {7: card},
		"main_deck": [Cards.battle(2, 2000, "D1")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_hand_card": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_invasion_observed(0, 4, 5)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp04_050_choice_b_discards_to_reduce_opponent_rage() -> void:
	var card := Real.instance("EBP04-050")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "hand": [Cards.battle(2, 2000, "H1")]},
		"p1": {"rage": 2},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1], "select_hand_card": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_invasion_observed(0, 4, 5)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[1].rage).is_equal(1)


func test_ebp04_050_silent_outside_zone_8_or_for_opponent_invasion() -> void:
	# Not in zone 8: no choice.
	var card := Real.instance("EBP04-050")
	var state := States.make_state({"p0": {"zone_cards": {4: card}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_invasion_observed(0, 4, 5)
	assert_int(input.count_calls("choose_option")).is_equal(0)

	# Someone else's monster invades: silent.
	var card2 := Real.instance("EBP04-050", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {7: card2}}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_invasion_observed(1, 4, 5)
	assert_int(input2.count_calls("choose_option")).is_equal(0)


# --- EBP04-051: enter in opp monster column → retreat TL<=30000 monster 1 ---


func test_ebp04_051_enter_retreats_low_threat_monster_in_same_column() -> void:
	var card := Real.instance("EBP04-051")
	# Zone 3 (idx 2) faces opponent zones 3/8 → opponent monster at zone 3 matches.
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(2)


func test_ebp04_051_stays_for_high_threat_or_off_column_monster() -> void:
	# Threat above 30000: no retreat.
	var card := Real.instance("EBP04-051")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}},
		"p1": {"monster_zone": 3, "current_monster": Cards.monster(3, 31000, [], "BIG")},
	})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# Opponent monster outside this card's column: silent.
	var card2 := Real.instance("EBP04-051", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {4: card2}},
		"p1": {"monster_zone": 3},
	})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(3)


# --- EBP04-052: opp-effect discard + opp in zones 4-8 → may play; zone 8 rage ---


func test_ebp04_052_plays_itself_when_opp_discards_it_and_opp_in_zones_4_8() -> void:
	var card := Real.instance("EBP04-052")
	var state := States.make_state({"p1": {"monster_zone": 4}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.active_player_id = 1
	handler.exec.active_card = Cards.strategy(2, "OPP-FX")

	await handler.trigger_discard_from_hand(0, card)

	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))


func test_ebp04_052_no_play_when_opp_monster_in_zones_1_3() -> void:
	var card := Real.instance("EBP04-052")
	var state := States.make_state({"p1": {"monster_zone": 3}})
	state.players[0].discard_pile.append(card)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.active_player_id = 1
	handler.exec.active_card = Cards.strategy(2, "OPP-FX")

	await handler.trigger_discard_from_hand(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_ebp04_052_zone8_gains_2_rage_when_opp_effect_discards_hand_cards() -> void:
	var card := Real.instance("EBP04-052")
	var state := States.make_state({"current_player_id": 1, "p0": {"zone_cards": {7: card}}})
	var s := _session(state)

	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 2000, "D"))
	assert_int(state.players[0].rage).is_equal(2)

	# Outside zone 8: no gain.
	var card2 := Real.instance("EBP04-052", 1)
	var state2 := States.make_state({"current_player_id": 1, "p0": {"zone_cards": {4: card2}}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 2000, "D"))
	assert_int(state2.players[0].rage).is_equal(0)

	# Own turn: TRIGGER_FILTERS gates it off.
	var card3 := Real.instance("EBP04-052", 2)
	var state3 := States.make_state({"p0": {"zone_cards": {7: card3}}})
	var s3 := _session(state3)
	await s3["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 2000, "D"))
	assert_int(state3.players[0].rage).is_equal(0)


# --- EBP04-053: enter swaps two of your battle cards ---


func test_ebp04_053_enter_swaps_two_chosen_zones() -> void:
	var card := Real.instance("EBP04-053")
	var other := Cards.battle(3, 3000, "OTHER")
	var state := States.make_state({"p0": {"zone_cards": {1: card, 3: other}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 3]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal(str(card.get("id")))
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal("OTHER")


func test_ebp04_053_skipping_or_lone_card_swaps_nothing() -> void:
	# 'May' effect: first pick can be skipped.
	var card := Real.instance("EBP04-053")
	var state := States.make_state({"p0": {"zone_cards": {1: card, 3: Cards.battle(3, 3000, "OTHER")}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, card)
	assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal(str(card.get("id")))

	# Fewer than 2 battle cards: no prompt at all.
	var card2 := Real.instance("EBP04-053", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {1: card2}}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(input2.count_calls("select_zone")).is_equal(0)


# --- EBP04-055: enter → destroy 4 other greens or destroy itself ---


func test_ebp04_055_self_destructs_with_fewer_than_4_other_greens() -> void:
	var card := Real.instance("EBP04-055")
	var state := States.make_state({"p0": {"zone_cards": {
		1: card,
		2: _green_battle(2, 2000, "G1"),
		3: _green_battle(2, 2000, "G2"),
		4: _green_battle(2, 2000, "G3"),
	}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_bool(state.players[0].zone_has_cards(1)).is_false()
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal(str(card.get("id")))
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_ebp04_055_paying_4_greens_keeps_it_alive() -> void:
	var card := Real.instance("EBP04-055")
	var state := States.make_state({"p0": {"zone_cards": {
		1: card,
		2: _green_battle(2, 2000, "G1"),
		3: _green_battle(2, 2000, "G2"),
		4: _green_battle(2, 2000, "G3"),
		5: _green_battle(2, 2000, "G4"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_zone": [2, 3, 4, 5]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(card.get("id")))
	for zi in [2, 3, 4, 5]:
		assert_bool(p0.zone_has_cards(zi)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(4)


func test_ebp04_055_declining_the_cost_destroys_itself() -> void:
	var card := Real.instance("EBP04-055")
	var state := States.make_state({"p0": {"zone_cards": {
		1: card,
		2: _green_battle(2, 2000, "G1"),
		3: _green_battle(2, 2000, "G2"),
		4: _green_battle(2, 2000, "G3"),
		5: _green_battle(2, 2000, "G4"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_bool(state.players[0].zone_has_cards(1)).is_false()
	assert_bool(state.players[0].zone_has_cards(2)).is_true()


# --- EBP04-059: revenge w/ 5+ green discards → recover a Rodan battle card ---


func test_ebp04_059_revenge_recovers_rodan_with_5_green_discards() -> void:
	var card := Real.instance("EBP04-059")
	var rodan := Cards.battle(3, 3000, "RD", [CardEnums.CardTrait.RODAN])
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)  # itself green + Rodan
	for i in range(4):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.players[0].discard_pile.append(rodan)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "RD"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_revenge(0, card)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("RD")
	# Pool offered both Rodan battle cards (this card may target itself).
	assert_int(_calls(input, "search_cards")[0]["matching"].size()).is_equal(2)


func test_ebp04_059_revenge_silent_below_5_green_discards() -> void:
	var card := Real.instance("EBP04-059")
	var state := States.make_state({})
	state.players[0].discard_pile.append(card)
	for i in range(3):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_revenge(0, card)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP04-062: revenge w/ 10 green → +1 rage per opp card in monster column ---


func test_ebp04_062_revenge_gains_rage_per_opponent_column_card() -> void:
	var card := Real.instance("EBP04-062")
	# Monster zone 3 (idx 2) → opponent column zones [2, 7].
	var state := States.make_state({
		"p0": {"monster_zone": 3},
		"p1": {
			"zone_cards": {2: Cards.battle(3, 3000, "OPP-A"), 7: Cards.battle(3, 3000, "OPP-B")},
			"monster_zone": 5,
		},
	})
	state.players[0].discard_pile.append(card)
	for i in range(9):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var s := _session(state)

	await s["effect_handler"].trigger_revenge(0, card)

	assert_int(state.players[0].rage).is_equal(2)


func test_ebp04_062_revenge_silent_below_10_green_or_empty_column() -> void:
	# 9 green battle cards: silent.
	var card := Real.instance("EBP04-062")
	var state := States.make_state({
		"p0": {"monster_zone": 3},
		"p1": {"zone_cards": {2: Cards.battle(3, 3000, "OPP-A")}, "monster_zone": 5},
	})
	state.players[0].discard_pile.append(card)
	for i in range(8):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var s := _session(state)
	await s["effect_handler"].trigger_revenge(0, card)
	assert_int(state.players[0].rage).is_equal(0)

	# Empty column: no rage even with 10 greens.
	var card2 := Real.instance("EBP04-062", 1)
	var state2 := States.make_state({"p0": {"monster_zone": 3}})
	state2.players[0].discard_pile.append(card2)
	for i in range(9):
		state2.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_revenge(0, card2)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP04-063: revenge → recover a Godzilla Earth battle card ---


func test_ebp04_063_revenge_recovers_godzilla_earth() -> void:
	var card := Real.instance("EBP04-063")
	var earth := Real.instance("EBP04-067")  # battle card with Godzilla Earth trait
	var state := States.make_state({})
	state.players[0].discard_pile.append_array([card, earth])
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": earth.get("id")}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_revenge(0, card)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal(str(earth.get("id")))
	# 063 itself isn't a Godzilla Earth card — only the real target matched.
	assert_int(_calls(input, "search_cards")[0]["matching"].size()).is_equal(1)


# --- EBP04-064: own counter start w/ 10 greens → may destroy self for rage -3 ---


func test_ebp04_064_destroys_itself_to_reduce_opponent_rage_3() -> void:
	var card := Real.instance("EBP04-064")
	var state := States.make_state({"p0": {"zone_cards": {3: card}}, "p1": {"rage": 3}})
	for i in range(10):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[0].zone_has_cards(3)).is_false()
	assert_int(state.players[1].rage).is_equal(0)


func test_ebp04_064_declining_or_below_10_greens_does_nothing() -> void:
	# Decline: stays in play, rage untouched.
	var card := Real.instance("EBP04-064")
	var state := States.make_state({"p0": {"zone_cards": {3: card}}, "p1": {"rage": 3}})
	for i in range(10):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_bool(state.players[0].zone_has_cards(3)).is_true()
	assert_int(state.players[1].rage).is_equal(3)

	# Only 9 greens: no prompt.
	var card2 := Real.instance("EBP04-064", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {3: card2}}, "p1": {"rage": 3}})
	for i in range(9):
		state2.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state2.current_phase = CardEnums.GamePhase.COUNTER
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input2.count_calls("choose_option")).is_equal(0)


# --- EBP04-067 + EBP04-T01: zone-8-only play, linked token in zone 3 ---


func test_ebp04_067_requires_zone_8_and_enter_creates_token_in_zone_3() -> void:
	var card := Real.instance("EBP04-067")
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_array(handler.get_card_required_play_zones(0, card)).contains_exactly([7])

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(CardUtils.base_id(p0.get_zone_top_card(2)))).is_equal("EBP04-T01")
	assert_str(str(p0.get_zone_top_card(7).get("id"))).is_equal(str(card.get("id")))


func test_ebp04_067_destroys_itself_when_token_zone_is_blocked_by_monster() -> void:
	var card := Real.instance("EBP04-067")
	var state := States.make_state({"p0": {"zone_cards": {7: card}, "monster_zone": 3}})
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.count_zone_tokens_by_id("EBP04-T01")).is_equal(0)


func test_ebp04_067_destroying_the_token_destroys_both() -> void:
	var card := Real.instance("EBP04-067")
	var token := Real.instance("EBP04-T01")
	var state := States.make_state({"p0": {"zone_cards": {7: card, 2: token}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_bool(p0.zone_has_cards(7)).is_false()
	# The token is BANISHED — only Godzilla Earth itself reaches the discard.
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp04_067_moving_the_main_card_destroys_both() -> void:
	var card := Real.instance("EBP04-067")
	var token := Real.instance("EBP04-T01")
	var state := States.make_state({"p0": {"zone_cards": {7: card, 2: token}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.swap_zones(state.players[0], 7, 6)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(6)).is_false()
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp04_t01_moving_the_token_destroys_both() -> void:
	var card := Real.instance("EBP04-067")
	var token := Real.instance("EBP04-T01")
	var state := States.make_state({"p0": {"zone_cards": {7: card, 2: token}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.move_zone_stack(state.players[0], 2, 4)

	var p0 := state.players[0]
	for zi in [2, 4, 7]:
		assert_bool(p0.zone_has_cards(zi)).is_false()
	# Token banished, main card discarded.
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal(str(card.get("id")))


# --- EBP04-072: opp deck-play while in zone 5 → search your deck ---


func test_ebp04_072_searches_deck_when_opponent_plays_from_deck() -> void:
	var card := Real.instance("EBP04-072")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"zone_cards": {4: card},
			"main_deck": [Cards.battle(2, 2000, "W1"), Cards.battle(2, 2000, "W2")],
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "W1"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_battle_card_played(1, Cards.battle(3, 3000, "OPP-PLAY"), 2, true)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("W1")
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	# Unfiltered search: the whole deck matched.
	assert_int(_calls(input, "search_cards")[0]["matching"].size()).is_equal(2)


func test_ebp04_072_silent_outside_zone_5_or_for_hand_plays() -> void:
	# Wrong zone: callback bails before the search.
	var card := Real.instance("EBP04-072")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {3: card}, "main_deck": [Cards.battle(2, 2000, "W1")]},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_battle_card_played(1, Cards.battle(3, 3000, "P"), 2, true)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Played from hand (not deck): TRIGGER_FILTERS gates it off.
	var card2 := Real.instance("EBP04-072", 1)
	var state2 := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {4: card2}, "main_deck": [Cards.battle(2, 2000, "W1")]},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_battle_card_played(1, Cards.battle(3, 3000, "P"), 2, false)
	assert_int(input2.count_calls("search_cards")).is_equal(0)


# --- EBP04-073: opp returns from discard while in zone 1 → recover a card ---


func test_ebp04_073_recovers_card_when_opponent_returns_from_discard() -> void:
	var card := Real.instance("EBP04-073")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {0: card}, "monster_zone": 4},
	})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "MINE"))
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "MINE"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_card_returned_from_discard(1, Cards.battle(2, 2000, "THEIRS"))

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("MINE")
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_ebp04_073_silent_outside_zone_1_or_for_own_returns() -> void:
	# Wrong zone.
	var card := Real.instance("EBP04-073")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {2: card}, "monster_zone": 4},
	})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "MINE"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_card_returned_from_discard(1, Cards.battle(2, 2000, "THEIRS"))
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# The owner returning their own card doesn't trigger it.
	var card2 := Real.instance("EBP04-073", 1)
	var state2 := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {0: card2}, "monster_zone": 4},
	})
	state2.players[0].discard_pile.append(Cards.battle(2, 2000, "MINE"))
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_card_returned_from_discard(0, Cards.battle(2, 2000, "RET"))
	assert_int(input2.count_calls("search_cards")).is_equal(0)


# --- EBP04-077: reveal 3, take a Mechagodzilla; named cards may play in zone 8 ---


func test_ebp04_077_plays_named_mech_into_zone_8() -> void:
	var card := Real.instance("EBP04-077")
	var mech := Real.instance("EBP04-043")  # "Multi-purpose Fighting System-3"
	var state := States.make_state({"p0": {
		"main_deck": [mech, Cards.battle(2, 2000, "F1"), Cards.battle(2, 2000, "F2"),
			Cards.battle(2, 2000, "BELOW")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": mech.get("id")}], "choose_option": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(7).get("id"))).is_equal(str(mech.get("id")))
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(2)
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("BELOW")


func test_ebp04_077_named_mech_may_stay_in_hand() -> void:
	var card := Real.instance("EBP04-077")
	var mech := Real.instance("EBP04-043")
	var state := States.make_state({"p0": {
		"main_deck": [mech, Cards.battle(2, 2000, "F1"), Cards.battle(2, 2000, "F2")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": mech.get("id")}], "choose_option": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal(str(mech.get("id")))
	assert_bool(state.players[0].zone_has_cards(7)).is_false()


func test_ebp04_077_other_mechs_go_to_hand_without_zone8_offer() -> void:
	var card := Real.instance("EBP04-077")
	var mech := Real.instance("EBP04-051")  # Super Mechagodzilla — not a named card
	var state := States.make_state({"p0": {
		"main_deck": [mech, Cards.battle(2, 2000, "F1"), Cards.battle(2, 2000, "F2")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": mech.get("id")}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_str(str(state.players[0].hand[0].get("id"))).is_equal(str(mech.get("id")))
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_ebp04_077_skipping_discards_all_revealed() -> void:
	var card := Real.instance("EBP04-077")
	var state := States.make_state({"p0": {
		"main_deck": [Real.instance("EBP04-043"), Cards.battle(2, 2000, "F1"), Cards.battle(2, 2000, "F2")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_int(input.count_calls("choose_option")).is_equal(0)


# --- EBP04-078: moves opp monster vertically from zones 3-5 ---


func test_ebp04_078_teleports_opponent_monster_vertically() -> void:
	var card := Real.instance("EBP04-078")
	var state := States.make_state({"p1": {"monster_zone": 3}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(8)

	var card2 := Real.instance("EBP04-078", 1)
	var state2 := States.make_state({"p1": {"monster_zone": 4}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(7)


func test_ebp04_078_silent_outside_zones_3_5() -> void:
	var card := Real.instance("EBP04-078")
	var state := States.make_state({"p1": {"monster_zone": 2}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(2)

	var card2 := Real.instance("EBP04-078", 1)
	var state2 := States.make_state({"p1": {"monster_zone": 6}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(6)


# --- EBP04-079: reveal 7, play all Final Wars battle cards, discard the rest ---


func test_ebp04_079_plays_all_final_wars_cards_from_reveal() -> void:
	var card := Real.instance("EBP04-079")
	var zilla := Real.instance("EBP04-039")     # Final Wars battle
	var anguirus := Real.instance("EBP04-040")  # Final Wars battle (enter gated off at mz 1)
	var state := States.make_state({"p0": {
		"main_deck": [zilla, Cards.battle(2, 2000, "N1"), anguirus, Cards.strategy(2, "N2"),
			Cards.battle(2, 2000, "N3")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"search_cards": [{"id": zilla.get("id")}, {"id": anguirus.get("id")}],
		"select_zone": [1, 2],
	}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(zilla.get("id")))
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(anguirus.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(3)
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp04_079_discards_everything_when_nothing_is_final_wars() -> void:
	var card := Real.instance("EBP04-079")
	var state := States.make_state({"p0": {
		"main_deck": [Cards.battle(2, 2000, "N1"), Cards.battle(2, 2000, "N2")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(2)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP04-080: evolve all rank<=3 Evolution battle cards in zones 1-5 ---


func test_ebp04_080_evolves_eligible_cards_in_zones_1_5() -> void:
	var card := Real.instance("EBP04-080")
	var larva := Real.instance("ESD02-007")     # rank 2, Evolution5 <Mothra>
	var larva_far := Real.instance("ESD02-007", 1)
	var imago := Real.instance("ESD02-010")     # rank 5 Mothra battle
	var state := States.make_state({"p0": {
		"monster_zone": 7,
		"zone_cards": {1: larva, 0: Cards.battle(2, 2000, "PLAIN"), 5: larva_far},
		"main_deck": [Cards.battle(1, 2000, "D1"), imago],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": imago.get("id")}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(imago.get("id")))
	assert_int(p0.get_zone_stack(1).size()).is_equal(2)
	# ESD02-010's own "if evolved, draw 1" fired.
	assert_int(p0.hand.size()).is_equal(1)
	# Zone 6 (idx 5) is outside zones 1-5: only one evolution prompt.
	assert_int(input.count_calls("search_cards")).is_equal(1)
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal(str(larva_far.get("id")))


func test_ebp04_080_skips_evolution_cards_above_rank_3() -> void:
	var card := Real.instance("EBP04-080")
	var monster_x := Real.instance("EBP04-047")  # rank 5 Evolution card
	var state := States.make_state({"p0": {
		"monster_zone": 7,
		"zone_cards": {2: monster_x},
		"main_deck": [Cards.battle(8, 9000, "KG", [CardEnums.CardTrait.KAISER_GHIDORAH])],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP04-085: returns from discard w/ 2 greens; protects Void Ghidorah ---


func test_ebp04_085_returns_to_hand_when_discarded_with_2_greens_in_play() -> void:
	var card := Real.instance("EBP04-085")
	var state := States.make_state({"p0": {
		"zone_cards": {1: _green_battle(2, 2000, "G1"), 2: _green_battle(2, 2000, "G2")},
		"strategy_zones": [card],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_strategy_zone(state.players[0], 0)

	var p0 := state.players[0]
	assert_bool(p0.strategy_zones[0].is_empty()).is_true()
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp04_085_stays_in_discard_below_2_greens() -> void:
	var card := Real.instance("EBP04-085")
	var state := States.make_state({"p0": {
		"zone_cards": {1: _green_battle(2, 2000, "G1")},
		"strategy_zones": [card],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_strategy_zone(state.players[0], 0)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp04_085_protects_void_ghidorah_in_zones_1_5_from_opp_effects() -> void:
	var card := Real.instance("EBP04-085")
	var void_g := Real.instance("EBP04-055")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {1: void_g}, "strategy_zones": [card]},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	# Opponent's effect on the opponent's turn: protected.
	handler.exec.active_player_id = 1
	handler.exec.active_card = Cards.strategy(2, "OPP-FX")
	assert_bool(handler.can_destroy_card(state.players[0], void_g)).is_false()

	# The owner's own effect is not blocked.
	handler.exec.active_player_id = 0
	assert_bool(handler.can_destroy_card(state.players[0], void_g)).is_true()

	# Owner's turn: the <Opponent's Turn> gate turns protection off.
	handler.exec.active_player_id = 1
	state.current_player_id = 0
	assert_bool(handler.can_destroy_card(state.players[0], void_g)).is_true()


func test_ebp04_085_does_not_protect_void_ghidorah_in_zones_6_8() -> void:
	var card := Real.instance("EBP04-085")
	var void_g := Real.instance("EBP04-055")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {6: void_g}, "strategy_zones": [card]},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.exec.active_player_id = 1
	handler.exec.active_card = Cards.strategy(2, "OPP-FX")
	assert_bool(handler.can_destroy_card(state.players[0], void_g)).is_true()


# --- EBP04-086: Base; own counter start plays 1 Vulture per 5 green discards ---


func test_ebp04_086_is_a_base_strategy() -> void:
	var card := Real.instance("EBP04-086")
	var state := States.make_state({})
	var s := _session(state)
	assert_bool(s["effect_handler"].is_base_strategy(card)).is_true()


func test_ebp04_086_plays_vultures_from_discard_per_5_greens() -> void:
	var card := Real.instance("EBP04-086")
	var v0 := Real.instance("EBP04-060")
	var v1 := Real.instance("EBP04-060", 1)
	var state := States.make_state({"p0": {"strategy_zones": [card]}})
	# 10 green battle cards in discard, two of them Vultures → 2 plays.
	state.players[0].discard_pile.append_array([v0, v1])
	for i in range(8):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"search_cards": [{"id": v0.get("id")}, {"id": v1.get("id")}],
		"select_zone": [1, 2],
	}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(1).get("id"))).is_equal(str(v0.get("id")))
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(v1.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(8)


func test_ebp04_086_silent_below_5_green_discards() -> void:
	var card := Real.instance("EBP04-086")
	var state := States.make_state({"p0": {"strategy_zones": [card]}})
	state.players[0].discard_pile.append(Real.instance("EBP04-060"))
	for i in range(3):
		state.players[0].discard_pile.append(_green_battle(2, 2000, "G%d" % i))
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP04-087: destroy up to 1 of each color in opp zones 1-5 ---


func test_ebp04_087_destroys_one_card_per_color() -> void:
	var card := Real.instance("EBP04-087")
	var state := States.make_state({
		"p1": {
			"zone_cards": {
				0: _colored_battle(2, 2000, "C-R", CardEnums.CardColor.RED),
				1: _colored_battle(2, 2000, "C-B", CardEnums.CardColor.BLUE),
				2: _colored_battle(2, 2000, "C-G", CardEnums.CardColor.GREEN),
				3: _colored_battle(2, 2000, "C-W", CardEnums.CardColor.WHITE),
				4: _colored_battle(2, 2000, "C-R2", CardEnums.CardColor.RED),
			},
			"monster_zone": 8,
		},
	})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0, 1, 2, 3]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p1 := state.players[1]
	for zi in [0, 1, 2, 3]:
		assert_bool(p1.zone_has_cards(zi)).is_false()
	assert_str(str(p1.get_zone_top_card(4).get("id"))).is_equal("C-R2")
	assert_int(p1.discard_pile.size()).is_equal(4)
	# After the red slot is consumed, the second red card is no longer offered.
	assert_bool(4 in input.calls[1]["valid"]).is_false()


func test_ebp04_087_skipping_destroys_nothing() -> void:
	var card := Real.instance("EBP04-087")
	var state := States.make_state({
		"p1": {"zone_cards": {0: Cards.battle(2, 2000, "C-R")}, "monster_zone": 8},
	})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(0)).is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(0)


# --- EBP04-089: Inherited Life — rage markers + milestones ---


func test_ebp04_089_claims_markers_on_own_turn_rage_decrease() -> void:
	var card := Real.instance("EBP04-089")
	var state := States.make_state({"p0": {"strategy_zones": [card], "rage": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.reduce_rage(0, 2)

	var p0 := state.players[0]
	assert_int(handler.get_cards_under_strategy_top(p0, 0).size()).is_equal(2)
	assert_int(p0.rage).is_equal(1)
	assert_int(p0.pending_rage_markers.size()).is_equal(0)


func test_ebp04_089_no_markers_on_opponent_turn_and_blocks_start_discard() -> void:
	var card := Real.instance("EBP04-089")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"strategy_zones": [card], "rage": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.reduce_rage(0, 2)
	assert_int(handler.get_cards_under_strategy_top(state.players[0], 0).size()).is_equal(0)

	# Anti-discard rule text (not <Base>).
	assert_bool(handler.prevents_self_start_phase_discard(0, card)).is_true()
	assert_bool(handler.is_base_strategy(card)).is_false()


func test_ebp04_089_milestones_15_22_and_30() -> void:
	var card := Real.instance("EBP04-089")
	var state := States.make_state({
		"p0": {"strategy_zones": [card], "rage": 15},
		"p1": {
			"zone_cards": {1: Cards.battle(2, 2000, "OPP-A"), 2: Cards.battle(2, 2000, "OPP-B")},
			"hand": [Cards.battle(1), Cards.battle(1), Cards.battle(1)],
			"monster_zone": 8,
		},
	})
	var winner: Array[int] = [-1]
	state.game_over.connect(func(winner_id: int, _reason: String) -> void: winner[0] = winner_id)
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	var p0 := state.players[0]
	var p1 := state.players[1]

	# 15th marker: all opponent battle cards destroyed; hand untouched.
	await handler.reduce_rage(0, 15)
	assert_int(handler.get_cards_under_strategy_top(p0, 0).size()).is_equal(15)
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_int(p1.hand.size()).is_equal(3)

	# 22nd marker: opponent discards their entire hand.
	p0.rage = 7
	await handler.reduce_rage(0, 7)
	assert_int(handler.get_cards_under_strategy_top(p0, 0).size()).is_equal(22)
	assert_int(p1.hand.size()).is_equal(0)
	assert_int(winner[0]).is_equal(-1)

	# 30th marker: the game is won.
	p0.rage = 8
	await handler.reduce_rage(0, 8)
	assert_int(handler.get_cards_under_strategy_top(p0, 0).size()).is_equal(30)
	assert_int(winner[0]).is_equal(0)
