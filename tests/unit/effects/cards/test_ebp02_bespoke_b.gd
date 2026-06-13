extends GdUnitTestSuite

## Tier C bespoke tests for EBP02 cards 042-T04 — one-of-a-kind effects driven
## through the real trigger-dispatch seam. See classification.md for the
## bespoke list. Cards 003-040 live in test_ebp02_bespoke_a.gd.

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


# --- EBP02-042: enter: discard KG/Megalon card → opp -2 rage; end start: +1 rage if opp in 1-5 ---


func test_ebp02_042_discards_ghidorah_card_to_drain_two_rage() -> void:
	var card := Real.instance("EBP02-042")
	var kg := Cards.battle(2, 2000, "KG", [CardEnums.CardTrait.KING_GHIDORAH])
	var state := States.make_state({
		"p0": {"current_monster": card, "hand": [kg, Cards.battle(2, 2000, "N")]},
		"p1": {"rage": 3},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
	# Only the King Ghidorah card was a legal cost.
	assert_array(input.calls[0]["valid"]).contains_exactly([0])


func test_ebp02_042_enter_silent_without_matching_hand_card() -> void:
	var card := Real.instance("EBP02-042")
	var state := States.make_state({
		"p0": {"current_monster": card, "hand": [Cards.battle(2, 2000, "N")]},
		"p1": {"rage": 3},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].rage).is_equal(3)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)


func test_ebp02_042_end_phase_rage_gain_only_with_opponent_in_zones_1_to_5() -> void:
	# Firing: own end phase, opponent in zone 5.
	var card := Real.instance("EBP02-042")
	var state := States.make_state({"p0": {"current_monster": card}, "p1": {"monster_zone": 5}})
	state.current_phase = CardEnums.GamePhase.END
	state.current_player_id = 0
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[0].rage).is_equal(1)

	# Opponent in zone 6: silent.
	var card2 := Real.instance("EBP02-042", 1)
	var state2 := States.make_state({"p0": {"current_monster": card2}, "p1": {"monster_zone": 6}})
	state2.current_phase = CardEnums.GamePhase.END
	state2.current_player_id = 0
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state2.players[0].rage).is_equal(0)

	# Opponent's end phase: TRIGGER_FILTERS gates it off.
	var card3 := Real.instance("EBP02-042", 2)
	var state3 := States.make_state({"current_player_id": 1, "p0": {"current_monster": card3}, "p1": {"monster_zone": 5}})
	state3.current_phase = CardEnums.GamePhase.END
	var s3 := _session(state3)
	var handler3: EffectHandler = s3["effect_handler"]
	await handler3.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state3.players[0].rage).is_equal(0)


# --- EBP02-044: invading w/ opp in 6-8 → opp -2 rage; end start w/ opp in 1-5 → +2 rage ---


func test_ebp02_044_invading_drains_rage_only_when_opponent_in_zones_6_to_8() -> void:
	var card := Real.instance("EBP02-044")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"monster_zone": 7, "rage": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_when_invading(0, 4, 5)
	assert_int(state.players[1].rage).is_equal(1)

	var card2 := Real.instance("EBP02-044", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": card2, "monster_zone": 4},
		"p1": {"monster_zone": 5, "rage": 3},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_when_invading(0, 4, 5)
	assert_int(state2.players[1].rage).is_equal(3)


func test_ebp02_044_end_phase_gains_two_rage_with_opponent_in_zones_1_to_5() -> void:
	var card := Real.instance("EBP02-044")
	var state := States.make_state({"p0": {"current_monster": card}, "p1": {"monster_zone": 3}})
	state.current_phase = CardEnums.GamePhase.END
	state.current_player_id = 0
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[0].rage).is_equal(2)

	var card2 := Real.instance("EBP02-044", 1)
	var state2 := States.make_state({"p0": {"current_monster": card2}, "p1": {"monster_zone": 6}})
	state2.current_phase = CardEnums.GamePhase.END
	state2.current_player_id = 0
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP02-046: enter: stack same-name cards from discard under; +3000 TL each ---


func test_ebp02_046_stacks_same_name_cards_from_discard_and_gains_threat() -> void:
	var card := Real.instance("EBP02-046")
	var copy1 := Real.instance("EBP02-046", 1)
	var copy2 := Real.instance("EBP02-046", 2)
	var state := States.make_state({"p0": {"current_monster": card}})
	state.players[0].discard_pile.append_array([copy1, Cards.monster(2, 9000, [], "OTHER"), copy2])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.monster_stack.size()).is_equal(2)
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("OTHER")
	assert_int(handler.get_threat_level_modifier(0)).is_equal(6000)


func test_ebp02_046_silent_without_same_name_cards_in_discard() -> void:
	var card := Real.instance("EBP02-046")
	var state := States.make_state({"p0": {"current_monster": card}})
	state.players[0].discard_pile.append(Cards.monster(2, 9000, [], "OTHER"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].monster_stack.size()).is_equal(0)
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)
	assert_int(input.count_calls("acknowledge_reveal")).is_equal(0)


# --- EBP02-048: enter mill 3; invading destroy 3 opp rank<=4 ---


func test_ebp02_048_enter_mills_three() -> void:
	var card := Real.instance("EBP02-048")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"main_deck": [Cards.battle(1, 1000, "D1"), Cards.battle(1, 1000, "D2"),
			Cards.battle(1, 1000, "D3"), Cards.battle(1, 1000, "D4")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_int(state.players[0].main_deck.size()).is_equal(1)


func test_ebp02_048_invading_destroys_three_rank4_and_lower() -> void:
	var card := Real.instance("EBP02-048")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2},
		"p1": {"zone_cards": {
			0: Cards.battle(4, 3000, "A"), 2: Cards.battle(3, 3000, "B"),
			4: Cards.battle(2, 2000, "C"), 6: Cards.battle(5, 4000, "R5"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0, 2, 4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 2, 3)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_bool(p1.zone_has_cards(4)).is_false()
	assert_str(str(p1.get_zone_top_card(6).get("id"))).is_equal("R5")


func test_ebp02_048_invading_silent_without_rank4_targets() -> void:
	var card := Real.instance("EBP02-048")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2},
		"p1": {"zone_cards": {6: Cards.battle(5, 4000, "R5")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 2, 3)

	assert_bool(state.players[1].zone_has_cards(6)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-049: enter w/ 3+ under → choose: destroy 3 r5- / opp discards to 3 / mill 3 ---


func test_ebp02_049_offers_available_options_and_resolves_hand_discard() -> void:
	var card := Real.instance("EBP02-049")
	var state := States.make_state({
		"p0": {"current_monster": card, "main_deck": [Cards.battle(1, 1000, "D1"), Cards.battle(1, 1000, "D2")]},
		"p1": {"hand": [Cards.battle(1), Cards.battle(2), Cards.battle(3), Cards.strategy(2), Cards.strategy(3)]},
	})
	for i in range(3):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U%d" % i))
	var input := ScriptedPlayerInput.new()
	# No opponent zone targets → options are [discard-to-3, mill-3]; pick the discard.
	input.answers = {"choose_option": [0], "choose_hand_discards": [[0, 1]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.calls[0]["options"].size()).is_equal(2)
	assert_int(state.players[1].hand.size()).is_equal(3)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(state.players[0].main_deck.size()).is_equal(2)


func test_ebp02_049_silent_with_fewer_than_three_cards_under() -> void:
	var card := Real.instance("EBP02-049")
	var state := States.make_state({
		"p0": {"current_monster": card, "main_deck": [Cards.battle(1, 1000, "D1")]},
		"p1": {"hand": [Cards.battle(1), Cards.battle(2), Cards.battle(3), Cards.strategy(2)]},
	})
	state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U0"))
	state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U1"))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(input.count_calls("choose_option")).is_equal(0)


# --- EBP02-050: enter w/ 5+ under → choose: destroy 3 r6- / opp to 2 / +3 rage ---


func test_ebp02_050_rage_option_auto_resolves_when_others_unavailable() -> void:
	var card := Real.instance("EBP02-050")
	var state := States.make_state({
		"p0": {"current_monster": card},
		"p1": {"hand": [Cards.battle(1), Cards.battle(2)]},
	})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	# No destroy targets, opp hand already <= 2 → rage option is the only one.
	assert_int(state.players[0].rage).is_equal(3)
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_ebp02_050_destroy_option_kills_rank6_target() -> void:
	var card := Real.instance("EBP02-050")
	var state := States.make_state({
		"p0": {"current_monster": card},
		"p1": {"hand": [Cards.battle(1), Cards.battle(2), Cards.battle(3), Cards.battle(4)],
			"zone_cards": {1: Cards.battle(6, 5000, "R6")}},
	})
	for i in range(5):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "select_zone": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.calls[0]["options"].size()).is_equal(3)
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_int(state.players[0].rage).is_equal(0)


func test_ebp02_050_silent_with_only_four_cards_under() -> void:
	var card := Real.instance("EBP02-050")
	var state := States.make_state({"p0": {"current_monster": card}})
	for i in range(4):
		state.players[0].monster_stack.append(Cards.monster(1, 4000, [], "U%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].rage).is_equal(0)
	assert_int(input.count_calls("choose_option")).is_equal(0)


# --- EBP02-052: invading: may discard 1 → play 1 Crystals token ---


func test_ebp02_052_discards_a_card_to_play_a_crystal() -> void:
	var card := Real.instance("EBP02-052")
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": 2,
		"hand": [Cards.battle(1, 1000, "H1"), Cards.strategy(2, "H2")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "select_zone": [3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 2, 3)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_int(p0.count_zone_tokens_by_id("EBP02-T03")).is_equal(1)
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal("EBP02-T03")


func test_ebp02_052_skipping_or_empty_hand_plays_nothing() -> void:
	# Skip the optional discard: no token.
	var card := Real.instance("EBP02-052")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 2, "hand": [Cards.battle(1)]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_when_invading(0, 2, 3)
	assert_int(state.players[0].count_zone_tokens_by_id("EBP02-T03")).is_equal(0)
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Empty hand: not even a prompt.
	var card2 := Real.instance("EBP02-052", 1)
	var state2 := States.make_state({"p0": {"current_monster": card2, "monster_zone": 2}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_when_invading(0, 2, 3)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)


# --- EBP02-053: invading: play 1 Crystals; +5000 TL with a Crystals in zones ---


func test_ebp02_053_invading_plays_crystal_and_unlocks_threat_bonus() -> void:
	var card := Real.instance("EBP02-053")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 2}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# No crystal yet: no bonus.
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)

	await handler.trigger_when_invading(0, 2, 3)

	assert_int(state.players[0].count_zone_tokens_by_id("EBP02-T03")).is_equal(1)
	# +5000 from the card, +1000 from the Crystals token itself (SpaceGodzilla monster).
	assert_int(handler.get_threat_level_modifier(0)).is_equal(6000)


# --- EBP02-054: enter: 2 Crystals; rage increase → destroy 1 r5- per Crystals ---


func test_ebp02_054_enter_plays_two_crystals_in_distinct_zones() -> void:
	var card := Real.instance("EBP02-054")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 1}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 2]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].count_zone_tokens_by_id("EBP02-T03")).is_equal(2)
	# Each token from one effect must land in a different zone.
	assert_array(input.calls[1]["valid"]).contains_exactly([2, 3, 4, 5, 6, 7])


func test_ebp02_054_rage_increase_destroys_one_target_per_crystal() -> void:
	var card := Real.instance("EBP02-054")
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {1: _token("EBP02-T03"), 2: _token("EBP02-T03")}},
		# Keep opponent targets out of the opponent's monster zone (idx 0) so the
		# crush rule doesn't eat them at the standby check timing.
		"p1": {"zone_cards": {
			1: Cards.battle(5, 4000, "OA"), 3: Cards.battle(4, 3000, "OB"), 5: Cards.battle(6, 5000, "OC"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.gain_rage(0, 1)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(3)).is_false()
	assert_str(str(p1.get_zone_top_card(5).get("id"))).is_equal("OC")


func test_ebp02_054_no_destroy_on_rage_decrease_or_without_crystals() -> void:
	# Rage decrease: TRIGGER_FILTERS direction gate keeps it silent.
	var card := Real.instance("EBP02-054")
	var state := States.make_state({
		"p0": {"current_monster": card, "rage": 2, "zone_cards": {1: _token("EBP02-T03")}},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OA")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.reduce_rage(0, 1)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Increase without any Crystals: silent.
	var card2 := Real.instance("EBP02-054", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": card2},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OA")}},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.gain_rage(0, 1)
	assert_bool(state2.players[1].zone_has_cards(1)).is_true()
	assert_int(input2.count_calls("select_zone")).is_equal(0)


# --- EBP02-056: +20,000 TL w/ 3+ Crystals; extra end-phase advance per Crystals (own turn) ---


func test_ebp02_056_threat_bonus_requires_three_crystals() -> void:
	var card := Real.instance("EBP02-056")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"zone_cards": {1: _token("EBP02-T03"), 2: _token("EBP02-T03")},
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	# 2 crystals: only the tokens' own +1000 each.
	assert_int(handler.get_threat_level_modifier(0)).is_equal(2000)

	state.players[0].push_zone_card(4, _token("EBP02-T03"))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(23000)


func test_ebp02_056_extra_end_phase_advance_counts_crystals_on_own_turn_only() -> void:
	var card := Real.instance("EBP02-056")
	var state := States.make_state({"p0": {
		"current_monster": card,
		"zone_cards": {1: _token("EBP02-T03"), 2: _token("EBP02-T03")},
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	state.current_player_id = 0
	assert_int(handler.get_extra_end_phase_advance(0)).is_equal(2)

	state.current_player_id = 1
	assert_int(handler.get_extra_end_phase_advance(0)).is_equal(0)


# --- EBP02-057: enter: move opp battle from own column; rage increase → 2 Crystals ---


func test_ebp02_057_enter_moves_opponent_card_out_of_its_column() -> void:
	var card := Real.instance("EBP02-057")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(3, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP")
	# Source pool was the column-facing occupied zones only.
	assert_array(input.calls[0]["valid"]).contains_exactly([1])


func test_ebp02_057_enter_silent_when_column_is_empty() -> void:
	var card := Real.instance("EBP02-057")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4},
		"p1": {"zone_cards": {5: Cards.battle(3, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(5)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(0)


func test_ebp02_057_rage_increase_plays_two_crystals() -> void:
	var card := Real.instance("EBP02-057")
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 1}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2, 4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.gain_rage(0, 1)

	assert_int(state.players[0].count_zone_tokens_by_id("EBP02-T03")).is_equal(2)


# --- EBP02-059: revenge: discard 1 → return "Godzilla(1991)" battle from discard ---


func test_ebp02_059_revenge_pays_discard_to_recover_godzilla_1991() -> void:
	var card := Real.instance("EBP02-059")
	var g91 := Real.instance("EBP02-065")  # battle named "Godzilla(1991)"
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"hand": [Cards.battle(1, 1000, "COST")],
	}})
	state.players[0].discard_pile.append(g91)
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "search_cards": [{"id": g91.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(g91.get("id")))
	# Discard holds the destroyed card and the cost.
	assert_int(p0.discard_pile.size()).is_equal(2)


func test_ebp02_059_revenge_silent_without_target_and_skippable() -> void:
	# No Godzilla(1991) in discard: no prompts at all.
	var card := Real.instance("EBP02-059")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "hand": [Cards.battle(1, 1000, "COST")]}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.destroy_zones(state.players[0], [2])
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Target exists but the cost is declined: no search.
	var card2 := Real.instance("EBP02-059", 1)
	var g91 := Real.instance("EBP02-065")
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}, "hand": [Cards.battle(1, 1000, "COST")]}})
	state2.players[0].discard_pile.append(g91)
	var input2 := ScriptedPlayerInput.new()
	input2.answers = {"select_hand_card": [-1]}
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.destroy_zones(state2.players[0], [2])
	assert_int(input2.count_calls("search_cards")).is_equal(0)
	assert_int(state2.players[0].hand.size()).is_equal(1)


# --- EBP02-060: +3000 CP in opp monster column; revenge w/ opp in 1-5 → back to hand ---


func test_ebp02_060_gains_3000_cp_facing_opponent_monster_column() -> void:
	var card := Real.instance("EBP02-060")
	var base: int = card.get("counter_power", 0)
	# Zone idx 2 faces opponent zones 3/8 → opp monster_zone 3 matches.
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base + 3000)

	state.players[1].monster_zone = 1
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base)


func test_ebp02_060_revenge_returns_to_hand_only_with_opponent_in_zones_1_to_5() -> void:
	var card := Real.instance("EBP02-060")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 4}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.destroy_zones(state.players[0], [2])
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(str(state.players[0].hand[0].get("id"))).is_equal(str(card.get("id")))
	assert_int(state.players[0].discard_pile.size()).is_equal(0)

	var card2 := Real.instance("EBP02-060", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}, "p1": {"monster_zone": 6}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.destroy_zones(state2.players[0], [2])
	assert_int(state2.players[0].hand.size()).is_equal(0)
	assert_int(state2.players[0].discard_pile.size()).is_equal(1)


# --- EBP02-064: +3000 CP w/ KG/Megalon in zones; revenge: KG monster discard → hand ---


func test_ebp02_064_gains_3000_cp_with_king_ghidorah_in_zones() -> void:
	var card := Real.instance("EBP02-064")
	var base: int = card.get("counter_power", 0)
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	# Alone (its own traits are Gigan/Weapon): no bonus.
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base)

	state.players[0].push_zone_card(4, Cards.battle(2, 2000, "KG", [CardEnums.CardTrait.KING_GHIDORAH]))
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base + 3000)


func test_ebp02_064_revenge_recovers_king_ghidorah_monster_from_discard() -> void:
	var card := Real.instance("EBP02-064")
	var kg_monster := Real.instance("EBP02-046")  # King Ghidorah monster
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append(kg_monster)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": kg_monster.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(kg_monster.get("id")))
	# The destroyed 064 (a KG-less Gigan battle) was not in the pool; nor are
	# KG battle cards — only KG MONSTER cards match.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP02-068: rank -2 per non-23 KG in discard; opp monster column → no invade, +3000 CP ---


func test_ebp02_068_play_rank_drops_2_per_non_rank23_ghidorah_in_discard() -> void:
	var card := Real.instance("EBP02-068")
	var state := States.make_state({"p0": {"hand": [card]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)

	var p0 := state.players[0]
	p0.discard_pile.append(Real.instance("EBP02-046"))      # KG monster rank 3 — counts
	p0.discard_pile.append(Real.instance("EBP02-064"))      # Gigan/Weapon traits only — ignored
	p0.discard_pile.append(Real.instance("EBP02-068", 1))   # KG but rank 23 — excluded
	p0.discard_pile.append(Cards.battle(2, 2000, "KG2", [CardEnums.CardTrait.KING_GHIDORAH]))  # counts
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-4)


func test_ebp02_068_blocks_invasion_and_gains_cp_in_opponent_monster_column() -> void:
	var card := Real.instance("EBP02-068")
	var base: int = card.get("counter_power", 0)
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_bool(handler.is_invasion_blocked(0)).is_true()
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base + 3000)

	state.players[1].monster_zone = 1
	assert_bool(handler.is_invasion_blocked(0)).is_false()
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(base)


# --- EBP02-069: swap 2 of the opponent's battle cards ---


func test_ebp02_069_swaps_two_opponent_battle_cards() -> void:
	var card := Real.instance("EBP02-069")
	var state := States.make_state({"p1": {"zone_cards": {
		1: Cards.battle(2, 2000, "OA"), 4: Cards.battle(3, 3000, "OB"), 6: Cards.battle(4, 4000, "OC"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1, 4]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_str(str(p1.get_zone_top_card(1).get("id"))).is_equal("OB")
	assert_str(str(p1.get_zone_top_card(4).get("id"))).is_equal("OA")
	assert_str(str(p1.get_zone_top_card(6).get("id"))).is_equal("OC")
	# The second pick can't be the first zone again.
	assert_array(input.calls[1]["valid"]).contains_exactly([4, 6])


func test_ebp02_069_silent_with_fewer_than_two_targets() -> void:
	var card := Real.instance("EBP02-069")
	var state := States.make_state({"p1": {"zone_cards": {1: Cards.battle(2, 2000, "OA")}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[1].get_zone_top_card(1).get("id"))).is_equal("OA")
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-070: opp can't play strategies; opp main start: discard to 5 → destroy this ---


func test_ebp02_070_blocks_opponent_strategy_plays_on_their_turn_only() -> void:
	var card := Real.instance("EBP02-070")
	var state := States.make_state({"current_player_id": 1})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_bool(handler.are_opponent_strategy_plays_blocked(1)).is_true()

	state.current_player_id = 0
	assert_bool(handler.are_opponent_strategy_plays_blocked(1)).is_false()


func test_ebp02_070_opponent_discards_to_five_to_destroy_it() -> void:
	var card := Real.instance("EBP02-070")
	var opp_hand: Array = []
	for i in range(7):
		opp_hand.append(Cards.battle(1, 1000, "H%d" % i))
	var state := States.make_state({"current_player_id": 1, "p1": {"hand": opp_hand}})
	state.players[0].strategy_zones[0] = card
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "choose_hand_discards": [[0]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_int(state.players[1].hand.size()).is_equal(5)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_true()
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal(str(card.get("id")))


func test_ebp02_070_survives_when_opponent_declines_or_hand_small() -> void:
	# Opponent declines the discard: the card stays.
	var card := Real.instance("EBP02-070")
	var opp_hand: Array = []
	for i in range(6):
		opp_hand.append(Cards.battle(1, 1000, "H%d" % i))
	var state := States.make_state({"current_player_id": 1, "p1": {"hand": opp_hand}})
	state.players[0].strategy_zones[0] = card
	state.current_phase = CardEnums.GamePhase.MAIN
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(state.players[1].hand.size()).is_equal(6)
	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_false()

	# Hand already <= 5: never prompts.
	var card2 := Real.instance("EBP02-070", 1)
	var state2 := States.make_state({"current_player_id": 1, "p1": {"hand": [Cards.battle(1), Cards.battle(2)]}})
	state2.players[0].strategy_zones[0] = card2
	state2.current_phase = CardEnums.GamePhase.MAIN
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)
	assert_bool(state2.players[0].strategy_zones[0].is_empty()).is_false()


# --- EBP02-071: choose: 3x r4- / Awakening6 2x r6- / Awakening8 1x any ---


func test_ebp02_071_awakening8_unlocks_all_three_options() -> void:
	var card := Real.instance("EBP02-071")
	var state := States.make_state({
		"p0": {"monster_zone": 8},
		"p1": {"zone_cards": {
			0: Cards.battle(4, 3000, "R4"), 1: Cards.battle(6, 5000, "R6"), 5: Cards.battle(7, 6000, "R7"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [2], "select_zone": [5]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.calls[0]["options"].size()).is_equal(3)
	assert_bool(state.players[1].zone_has_cards(5)).is_false()
	assert_bool(state.players[1].zone_has_cards(0)).is_true()
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


func test_ebp02_071_without_awakening_only_rank4_option_auto_resolves() -> void:
	var card := Real.instance("EBP02-071")
	var state := States.make_state({
		"p0": {"monster_zone": 1},
		"p1": {"zone_cards": {0: Cards.battle(4, 3000, "R4"), 1: Cards.battle(6, 5000, "R6")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(0)).is_false()
	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	# Destroy 3 with only one legal target: only one zone prompt fires.
	assert_int(input.count_calls("select_zone")).is_equal(1)


func test_ebp02_071_silent_with_no_targets() -> void:
	var card := Real.instance("EBP02-071")
	var state := States.make_state({
		"p0": {"monster_zone": 1},
		"p1": {"zone_cards": {1: Cards.battle(6, 5000, "R6")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-074: gain 1 rage per opponent monster rank ---


func test_ebp02_074_gains_rage_equal_to_opponent_monster_rank() -> void:
	var card := Real.instance("EBP02-074")
	var state := States.make_state({"p1": {"current_monster": Cards.monster(3, 20000, [], "OPP-R3")}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].rage).is_equal(3)


# --- EBP02-075: enter w/ "Chibi Mechagodzilla" in zones → opp -1 rage ---


func test_ebp02_075_reduces_rage_only_with_chibi_mechagodzilla_present() -> void:
	var card := Real.instance("EBP02-075")
	var mecha := Real.instance("EBP02-076")  # named "Chibi Mechagodzilla"
	var state := States.make_state({"p0": {"zone_cards": {2: card, 1: mecha}}, "p1": {"rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)

	var card2 := Real.instance("EBP02-075", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}, "p1": {"rage": 2}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(2)


# --- EBP02-077: own main start: mill 2; if Godzilla milled → destroy self, play 2nd Form token ---


func test_ebp02_077_transforms_when_a_godzilla_is_milled() -> void:
	var card := Real.instance("EBP02-077")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(2, 2000, "GOJI", [CardEnums.CardTrait.GODZILLA]), Cards.battle(2, 2000, "N1")],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [5]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal("EBP02-T04")
	# Discard: 2 milled cards + the destroyed Chibi Godzilla itself.
	assert_int(p0.discard_pile.size()).is_equal(3)
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp02_077_just_mills_when_no_godzilla_is_hit() -> void:
	var card := Real.instance("EBP02-077")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(2, 2000, "N1"), Cards.strategy(2, "N2")],
	}})
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(2)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- EBP02-078: enter in opp monster column → reveal 2, keep rank<=5 battle cards ---


func test_ebp02_078_reveals_two_and_keeps_low_rank_battle_cards() -> void:
	var card := Real.instance("EBP02-078")
	# Zone idx 2 faces opponent zones 3/8 → opp monster_zone 3 matches.
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "main_deck": [Cards.battle(5, 4000, "LOW"), Cards.battle(6, 5000, "HIGH")]},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("LOW")
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("HIGH")
	assert_int(p0.main_deck.size()).is_equal(0)


func test_ebp02_078_silent_outside_opponent_monster_column() -> void:
	var card := Real.instance("EBP02-078")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "main_deck": [Cards.battle(5, 4000, "LOW"), Cards.battle(6, 5000, "HIGH")]},
		"p1": {"monster_zone": 1},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].main_deck.size()).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(0)


# --- EBP02-079: destroy tier scales with invasion zones crossed this turn ---


func test_ebp02_079_two_zones_crossed_destroys_up_to_rank_6() -> void:
	var card := Real.instance("EBP02-079")
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(2, 2000, "R2"), 2: Cards.battle(6, 5000, "R6"), 4: Cards.battle(7, 6000, "R7"),
	}}})
	state.players[0].invasion_zones_crossed = 2
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_false()
	assert_str(str(p1.get_zone_top_card(4).get("id"))).is_equal("R7")


func test_ebp02_079_zero_zones_crossed_destroys_only_rank_2_and_lower() -> void:
	var card := Real.instance("EBP02-079")
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(2, 2000, "R2"), 2: Cards.battle(4, 3000, "R4"),
	}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_str(str(p1.get_zone_top_card(2).get("id"))).is_equal("R4")


# --- EBP02-080: reveal 2 — hand if traits differ, discard otherwise ---


func test_ebp02_080_keeps_pair_with_differing_traits() -> void:
	var card := Real.instance("EBP02-080")
	var state := States.make_state({"p0": {"main_deck": [
		Cards.battle(2, 2000, "GA", [CardEnums.CardTrait.GODZILLA]),
		Cards.battle(2, 2000, "MA", [CardEnums.CardTrait.MOTHRA]),
	]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(2)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_ebp02_080_discards_identical_or_traitless_pairs() -> void:
	# Identical traits: both discarded.
	var card := Real.instance("EBP02-080")
	var state := States.make_state({"p0": {"main_deck": [
		Cards.battle(2, 2000, "GA", [CardEnums.CardTrait.GODZILLA]),
		Cards.battle(3, 3000, "GB", [CardEnums.CardTrait.GODZILLA]),
	]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(2)

	# A traitless card can't "differ in a trait": both discarded.
	var card2 := Real.instance("EBP02-080", 1)
	var state2 := States.make_state({"p0": {"main_deck": [
		Cards.strategy(2, "S"),
		Cards.battle(2, 2000, "GA", [CardEnums.CardTrait.GODZILLA]),
	]}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[0].hand.size()).is_equal(0)
	assert_int(state2.players[0].discard_pile.size()).is_equal(2)


# --- EBP02-T04: own end start: destroy self (banish), play "Chibi Godzilla" from discard ---


func test_ebp02_t04_end_phase_swaps_back_to_chibi_godzilla_from_discard() -> void:
	var token := _token("EBP02-T04")
	var chibi := Real.instance("EBP02-077")  # named "Chibi Godzilla"
	var state := States.make_state({"p0": {"zone_cards": {4: token}}})
	state.players[0].discard_pile.append(chibi)
	state.current_phase = CardEnums.GamePhase.END
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": chibi.get("id")}], "select_zone": [6]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(4)).is_false()
	assert_str(str(p0.get_zone_top_card(6).get("id"))).is_equal(str(chibi.get("id")))
	# The token is banished, not discarded.
	assert_int(p0.discard_pile.size()).is_equal(0)


func test_ebp02_t04_banishes_itself_even_without_a_chibi_godzilla() -> void:
	var token := _token("EBP02-T04")
	var state := States.make_state({"p0": {"zone_cards": {4: token}}})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "OTHER"))
	state.current_phase = CardEnums.GamePhase.END
	state.current_player_id = 0
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(4)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_int(input.count_calls("select_zone")).is_equal(0)
