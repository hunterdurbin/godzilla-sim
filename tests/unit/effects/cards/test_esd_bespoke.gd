extends GdUnitTestSuite

## Tier C bespoke tests for the small sets (ESD01, ESD02, EFC01, ESC01) —
## one-of-a-kind effects driven through the real trigger-dispatch seam.
## See classification.md for the bespoke lists.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


# --- ESD01-010: City of Tokyo — field CP to zone 8 (rage>=2 / Awakening6) ---


func test_esd01_010_boosts_zone8_by_rage_and_awakening() -> void:
	var card := Real.instance("ESD01-010")
	var zone8 := Cards.battle(5, 3000, "Z8")
	var state := States.make_state({"p0": {"zone_cards": {2: card, 7: zone8}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	# Neither condition: no boost.
	assert_int(handler.get_effective_zone_cp(0, 7)).is_equal(3000)
	# Rage >= 2: +5000.
	state.players[0].rage = 2
	assert_int(handler.get_effective_zone_cp(0, 7)).is_equal(8000)
	# Rage >= 2 AND Awakening6: +10000.
	state.players[0].monster_zone = 6
	assert_int(handler.get_effective_zone_cp(0, 7)).is_equal(13000)
	# Awakening6 only: +5000.
	state.players[0].rage = 0
	assert_int(handler.get_effective_zone_cp(0, 7)).is_equal(8000)


func test_esd01_010_does_not_boost_itself_in_zone8() -> void:
	var card := Real.instance("ESD01-010")
	var state := States.make_state({"p0": {"zone_cards": {7: card}, "rage": 2, "monster_zone": 6}})
	var s := _session(state)
	# "Other" battle card — its own zone gets no bonus (base CP is 0).
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 7)) \
		.is_equal(int(card.get("counter_power", -1)))


# --- ESD01-011: enter reduces opp rage at rage>=2; destroyed → deck bottom ---


func test_esd01_011_enter_reduces_opponent_rage_only_with_rage_2() -> void:
	var card := Real.instance("ESD01-011")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "rage": 2}, "p1": {"rage": 3}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(2)

	var card2 := Real.instance("ESD01-011", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}, "rage": 1}, "p1": {"rage": 3}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(3)


func test_esd01_011_destroyed_goes_to_deck_bottom_instead_of_discard() -> void:
	var card := Real.instance("ESD01-011")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2")],
	}})
	var s := _session(state)
	# Typed handler var: destroy_zones takes Array[int]; a dynamic call through
	# the session Dictionary would pass an untyped Array and abort at runtime.
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [2])

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("ESD01-011 should sit at the deck bottom after destruction") \
		.is_equal(str(card.get("id")))


# --- ESD01-012: move to empty zone on own monster played; +3000 CP in zone 8 ---


func test_esd01_012_moves_to_chosen_empty_zone_on_own_monster_played() -> void:
	var card := Real.instance("ESD01-012")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [5]}
	var state_session := States.make_session(state, input)

	await state_session["effect_handler"].trigger_monster_played(0, {}, state.players[0].current_monster)

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_str(str(state.players[0].get_zone_top_card(5).get("id"))).is_equal(str(card.get("id")))


func test_esd01_012_stays_when_skipped_and_silent_on_opponent_turn() -> void:
	var card := Real.instance("ESD01-012")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_monster_played(0, {}, state.players[0].current_monster)
	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal(str(card.get("id")))

	# Opponent's turn: the effect must not even prompt.
	state.current_player_id = 1
	await s["effect_handler"].trigger_monster_played(0, {}, state.players[0].current_monster)
	assert_int(input.count_calls("select_zone")).is_equal(1)


func test_esd01_012_gains_3000_cp_in_zone_8() -> void:
	var card := Real.instance("ESD01-012")
	var base: int = card.get("counter_power", 0)
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	var s := _session(state)
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 7)).is_equal(base + 3000)

	var card2 := Real.instance("ESD01-012", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}})
	var s2 := _session(state2)
	assert_int(s2["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base)


# --- ESD01-014: Godzilla Emerges — search + play Godzilla(2023) at rage>=2 ---


func test_esd01_014_plays_godzilla_2023_from_deck_when_rage_2() -> void:
	var card := Real.instance("ESD01-014")
	var target := Real.instance("ESD01-011")  # battle card named Godzilla(2023)
	var state := States.make_state({"p0": {
		"rage": 2,
		"main_deck": [Cards.battle(1, 2000, "D1"), target, Cards.strategy(2, "D2")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}], "select_zone": [3]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].main_deck.size()).is_equal(2)
	# Search pool was name+type filtered: only the Godzilla(2023) battle card.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


func test_esd01_014_does_nothing_below_rage_2() -> void:
	var card := Real.instance("ESD01-014")
	var state := States.make_state({"p0": {
		"rage": 1,
		"main_deck": [Real.instance("ESD01-011")],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- ESD02-003: play 2 rank<=4 Evolution battle cards from discard adjacent ---


func test_esd02_003_plays_two_evolution_cards_from_discard_adjacent_to_monster() -> void:
	var monster := Real.instance("ESD02-003")
	var evo_a := Real.instance("ESD02-007")  # rank 2, Evolution
	var evo_b := Real.instance("ESD02-008")  # rank 3, Evolution
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4}})
	var p0 := state.players[0]
	p0.discard_pile.append_array([evo_a, evo_b, Cards.battle(5, 4000, "NO-EVO")])
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"search_cards": [{"id": evo_a.get("id")}, {"id": evo_b.get("id")}],
		"select_zone": [2, 4],
	}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(evo_a.get("id")))
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal(str(evo_b.get("id")))
	assert_int(p0.discard_pile.size()).is_equal(1)
	# Pool only offered Evolution battle cards of rank <= 4.
	assert_int(input.calls[0]["matching"].size()).is_equal(2)
	# Rule 5.11.1.3: second placement must not offer the zone already used.
	assert_bool(2 in input.calls[3]["valid"]).is_false()


# --- ESD02-004: invading, discard battle from hand → destroy all opp <= rank ---


func test_esd02_004_destroys_all_opponent_cards_up_to_discarded_rank() -> void:
	var monster := Real.instance("ESD02-004")
	var state := States.make_state({
		"p0": {
			"current_monster": monster, "monster_zone": 4,
			"hand": [Cards.battle(4, 3000, "COST"), Cards.strategy(2, "S")],
		},
		"p1": {"zone_cards": {
			1: Cards.battle(4, 3000, "OPP-R4A"),
			5: Cards.battle(4, 3000, "OPP-R4B"),
			3: Cards.battle(5, 4000, "OPP-R5"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 4, 5)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(5)).is_false()
	assert_str(str(p1.get_zone_top_card(3).get("id"))).is_equal("OPP-R5")
	assert_int(p1.discard_pile.size()).is_equal(2)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)  # the cost


func test_esd02_004_skipping_the_cost_destroys_nothing() -> void:
	var monster := Real.instance("ESD02-004")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 4, "hand": [Cards.battle(4, 3000, "COST")]},
		"p1": {"zone_cards": {1: Cards.battle(2, 3000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 4, 5)

	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(state.players[0].hand.size()).is_equal(1)


# --- ESD02-009: Super-X — Awakening4 + zone 8 → reduce opp rage 1 ---


func test_esd02_009_reduces_rage_only_with_awakening4_in_zone8() -> void:
	# Firing: monster_zone 4, card in zone 8.
	var card := Real.instance("ESD02-009")
	var state := States.make_state({"p0": {"zone_cards": {7: card}, "monster_zone": 4}, "p1": {"rage": 2}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)

	# No awakening: silent.
	var card2 := Real.instance("ESD02-009", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {7: card2}, "monster_zone": 3}, "p1": {"rage": 2}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(2)

	# Wrong zone: silent.
	var card3 := Real.instance("ESD02-009", 2)
	var state3 := States.make_state({"p0": {"zone_cards": {2: card3}, "monster_zone": 4}, "p1": {"rage": 2}})
	var s3 := _session(state3)
	await s3["effect_handler"].trigger_enter(0, card3)
	assert_int(state3.players[1].rage).is_equal(2)


# --- ESD02-014: evolve one of your Evolution battle cards ---


func test_esd02_014_evolves_chosen_battle_card() -> void:
	var card := Real.instance("ESD02-014")
	var larva := Real.instance("ESD02-007")   # Evolution5 <Mothra>
	var imago := Real.instance("ESD02-010")   # rank 5 Mothra battle
	var state := States.make_state({"p0": {
		"zone_cards": {2: larva},
		"main_deck": [Cards.battle(1, 2000, "D1"), imago],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2], "search_cards": [{"id": imago.get("id")}]}
	var s := States.make_session(state, input)
	var log_tokens: Array[Dictionary] = []
	var handler: EffectHandler = s["effect_handler"]
	handler.log_message.connect(func(t: Dictionary) -> void: log_tokens.append(t))

	await handler.trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(imago.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# ESD02-010's own enter ("if evolved, draw 1") fires via the evolution.
	assert_int(p0.hand.size()).is_equal(1)
	# The evolution log token carries the Enter marker for the evolved card.
	var evo_tokens := log_tokens.filter(func(t: Dictionary) -> bool: return t.get("type") == "evolution")
	assert_int(evo_tokens.size()).is_equal(1)
	assert_bool(evo_tokens[0].get("has_enter", false)).is_true()


func test_esd02_014_evolution_log_has_no_enter_for_plain_target() -> void:
	var card := Real.instance("ESD02-014")
	var larva := Real.instance("ESD02-007")   # Evolution5 <Mothra>
	var plain := Cards.battle(5, 2000, "PLAIN-MOTHRA", [CardEnums.CardTrait.MOTHRA])
	var state := States.make_state({"p0": {
		"zone_cards": {2: larva},
		"main_deck": [Cards.battle(1, 2000, "D1"), plain],
	}})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2], "search_cards": [{"id": "PLAIN-MOTHRA"}]}
	var s := States.make_session(state, input)
	var log_tokens: Array[Dictionary] = []
	var handler: EffectHandler = s["effect_handler"]
	handler.log_message.connect(func(t: Dictionary) -> void: log_tokens.append(t))

	await handler.trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(2).get("id"))).is_equal("PLAIN-MOTHRA")
	var evo_tokens := log_tokens.filter(func(t: Dictionary) -> bool: return t.get("type") == "evolution")
	assert_int(evo_tokens.size()).is_equal(1)
	assert_bool(evo_tokens[0].get("has_enter", false)).is_false()


# --- EFC01-002: adjacent to monster → mill 1; if battle, recover a monster ---


func test_efc01_002_mills_and_recovers_monster_when_adjacent() -> void:
	var card := Real.instance("EFC01-002")
	var recoverable := Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "DISC-MON")
	# Monster at zone 4 (idx 3): adjacent zones are idx 2, 4, 6.
	var state := States.make_state({"p0": {
		"zone_cards": {4: card},
		"monster_zone": 4,
		"main_deck": [Cards.battle(1, 2000, "TOP-BATTLE"), Cards.battle(1, 2000, "D2")],
	}})
	state.players[0].discard_pile.append(recoverable)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DISC-MON"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.main_deck.size()).is_equal(1)
	assert_str(str(p0.hand[0].get("id"))).is_equal("DISC-MON")
	# Discard holds only the milled battle card now.
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("TOP-BATTLE")


func test_efc01_002_silent_when_not_adjacent_or_mills_non_battle() -> void:
	# Not adjacent: no mill at all.
	var card := Real.instance("EFC01-002")
	var state := States.make_state({"p0": {
		"zone_cards": {0: card}, "monster_zone": 4,
		"main_deck": [Cards.battle(1, 2000, "TOP")],
	}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].main_deck.size()).is_equal(1)

	# Adjacent but mills a strategy: no recovery prompt.
	var card2 := Real.instance("EFC01-002", 1)
	var state2 := States.make_state({"p0": {
		"zone_cards": {4: card2}, "monster_zone": 4,
		"main_deck": [Cards.strategy(2, "TOP-STRATEGY")],
	}})
	state2.players[0].discard_pile.append(Cards.monster(2, 9000, [], "DISC-MON2"))
	var input := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[0].main_deck.size()).is_equal(0)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EFC01-003: discard Gigan+Fest → search Weapon/Mech Invade-2 battle ---


func test_efc01_003_discard_cost_then_searches_weapon_or_mech_invade2() -> void:
	var card := Real.instance("EFC01-003")
	var cost := Cards.battle(2, 2000, "GF", [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.FEST])
	var wanted := Cards.battle(3, 3000, "WPN", [CardEnums.CardTrait.WEAPON], 2)
	var decoy := Cards.battle(3, 3000, "WPN-INV1", [CardEnums.CardTrait.WEAPON], 1)
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"hand": [cost, Cards.battle(2, 2000, "OTHER")],
		"main_deck": [decoy, wanted],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0], "search_cards": [{"id": "WPN"}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("GF")
	assert_bool(p0.hand.any(func(c: Dictionary) -> bool: return c.get("id") == "WPN")).is_true()
	assert_int(p0.main_deck.size()).is_equal(1)
	# The invade-1 weapon was filtered out of the search pool.
	assert_int(input.calls[1]["matching"].size()).is_equal(1)


func test_efc01_003_skipping_discard_skips_search() -> void:
	var card := Real.instance("EFC01-003")
	var cost := Cards.battle(2, 2000, "GF", [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.FEST])
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"hand": [cost],
		"main_deck": [Cards.battle(3, 3000, "WPN", [CardEnums.CardTrait.WEAPON], 2)],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EFC01-005: monster played → reveal 5, Fest to hand; counter → dump hand ---


func test_efc01_005_reveals_five_keeps_fest_cards() -> void:
	var card := Real.instance("EFC01-005")
	var deck: Array[Dictionary] = [
		Cards.battle(2, 2000, "F1", [CardEnums.CardTrait.FEST]),
		Cards.battle(2, 2000, "N1"),
		Cards.battle(2, 2000, "F2", [CardEnums.CardTrait.FEST]),
		Cards.strategy(2, "N2"),
		Cards.battle(2, 2000, "N3"),
		Cards.battle(2, 2000, "BELOW"),
	]
	var state := States.make_state({"p0": {"main_deck": deck}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)

	await s["effect_handler"].trigger_monster_played(0, {}, state.players[0].current_monster)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(2)
	assert_int(p0.discard_pile.size()).is_equal(3)
	assert_int(p0.main_deck.size()).is_equal(1)
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("BELOW")


func test_efc01_005_discards_hand_at_own_counter_phase_only() -> void:
	var card := Real.instance("EFC01-005")
	var state := States.make_state({"p0": {"hand": [Cards.battle(2), Cards.strategy(2, "S")]}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)

	# Wrong phase: nothing happens (TRIGGER_FILTERS gates it off).
	state.current_phase = CardEnums.GamePhase.MAIN
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(state.players[0].hand.size()).is_equal(2)

	# Opponent's counter phase: still silent.
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.COUNTER
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].hand.size()).is_equal(2)

	# Own counter phase: hand discarded.
	state.current_player_id = 0
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


# --- ESC01-001: -4 self play rank with Godzilla in hand; column CP; counter ---


func test_esc01_001_play_rank_minus_4_only_with_godzilla_in_hand() -> void:
	var card := Real.instance("ESC01-001")
	var godzilla := Cards.battle(2, 2000, "GOJI", [CardEnums.CardTrait.GODZILLA])
	var state := States.make_state({"p0": {"hand": [card, godzilla]}})
	var s := _session(state)
	assert_int(s["effect_handler"].get_play_rank_modifier(0, card)).is_equal(-4)

	state.players[0].hand.remove_at(1)
	assert_int(s["effect_handler"].get_play_rank_modifier(0, card)).is_equal(0)


func test_esc01_001_gains_3000_cp_in_opponent_monster_column() -> void:
	var card := Real.instance("ESC01-001")
	var base: int = card.get("counter_power", 0)
	# Zone idx 2 faces opponent zones 3/8 → opponent monster_zone 3 matches.
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"monster_zone": 3}})
	var s := _session(state)
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base + 3000)

	state.players[1].monster_zone = 1
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base)


func test_esc01_001_returns_to_deck_bottom_on_counter_success() -> void:
	var card := Real.instance("ESC01-001")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	var s := _session(state)

	await s["effect_handler"].trigger_counter_success(0, 1)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_str(str(p0.main_deck.back().get("id"))).is_equal(str(card.get("id")))
