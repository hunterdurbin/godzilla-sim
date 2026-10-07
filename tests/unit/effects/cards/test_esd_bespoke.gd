extends GdUnitTestSuite

## Tier C bespoke tests for the small sets (ESD01–ESD05, EFC01, ESC01) —
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
	# Replacement: the card never counts as destroyed.
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)


func test_esd01_011_overloaded_by_play_goes_to_deck_bottom() -> void:
	# Overload IS <Destroy> (11.5.1), so the replacement applies when a card
	# is played over ESD01-011.
	var card := Real.instance("ESD01-011")
	var attacker := Cards.battle(2, 2000, "OVER")
	var state := States.make_state({"p0": {
		"hand": [attacker],
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2")],
	}})
	var s := _session(state)

	await s["action_handler"].execute(
		CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 2}, state)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("OVER")
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("ESD01-011 should sit at the deck bottom after being overloaded") \
		.is_equal(str(card.get("id")))
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)


func test_esd01_011_crushed_goes_to_deck_bottom_without_crush_event() -> void:
	# Crush IS <Destroy> (11.3.3): replaced instead — no destroy count, no
	# battle_card_crushed emission.
	var card := Real.instance("ESD01-011")
	var state := States.make_state({"p0": {
		"monster_zone": 3,
		"zone_cards": {2: card},
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	var s := _session(state)
	var crushed: Array = []
	s["events"].battle_card_crushed.connect(func(_pid: int, _z: int, c: Dictionary) -> void:
		crushed.append(c))

	await s["action_handler"].resolve_check_timing(state)

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(2)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("ESD01-011 should sit at the deck bottom after being crushed") \
		.is_equal(str(card.get("id")))
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)
	assert_array(crushed).is_empty()


# --- ESD01-012: move to empty zone on own monster played; +3000 CP in zone 8 ---


func test_esd01_012_destroyed_goes_to_deck_bottom_instead_of_discard() -> void:
	var card := Real.instance("ESD01-012")
	var state := States.make_state({"p0": {
		"zone_cards": {4: card},
		"main_deck": [Cards.battle(1, 2000, "D1"), Cards.battle(1, 2000, "D2")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_zones(state.players[0], [4])

	var p0 := state.players[0]
	assert_bool(p0.zone_has_cards(4)).is_false()
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("ESD01-012 should sit at the deck bottom after destruction") \
		.is_equal(str(card.get("id")))
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)


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


# --- ESC01-002: enter plays rank<=3 Evolution battle card from discard, evolves it ---


func test_esc01_002_plays_from_discard_and_evolves() -> void:
	var card := Real.instance("ESC01-002")
	var evo := Cards.battle(3, 3000, "EVO")
	evo["evolution_rank"] = 5
	evo["evolution_trait"] = CardEnums.CardTrait.GODZILLA
	var big := Cards.battle(5, 8000, "BIG", [CardEnums.CardTrait.GODZILLA])
	var state := States.make_state({"p0": {"current_monster": card, "main_deck": [big]}})
	state.players[0].discard_pile.append(evo)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [evo, big], "select_zone": [2]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.get_zone_top_card(2).get("id"))) \
		.override_failure_message("evolved card should sit on top of the played one") \
		.is_equal("BIG")
	assert_int(p0.main_deck.size()).is_equal(0)


func test_esc01_002_offers_only_rank3_or_lower_evolution_battle_cards() -> void:
	var card := Real.instance("ESC01-002")
	var too_big := Cards.battle(4, 3000, "R4")
	too_big["evolution_rank"] = 5
	too_big["evolution_trait"] = CardEnums.CardTrait.GODZILLA
	var plain := Cards.battle(3, 3000, "R3P")
	var state := States.make_state({"p0": {"current_monster": card}})
	state.players[0].discard_pile.append(too_big)
	state.players[0].discard_pile.append(plain)
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(2)
	var matching: Array = input.calls[0]["matching"]
	assert_bool(matching.is_empty()) \
		.override_failure_message("rank 4 / non-Evolution cards must not be selectable") \
		.is_true()


func test_esc01_002_may_skip() -> void:
	var card := Real.instance("ESC01-002")
	var evo := Cards.battle(2, 3000, "EVO")
	evo["evolution_rank"] = 5
	evo["evolution_trait"] = CardEnums.CardTrait.GODZILLA
	var state := States.make_state({"p0": {"current_monster": card}})
	state.players[0].discard_pile.append(evo)
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].discard_pile.size()).is_equal(1)


# --- ESC01-003: enter in zone 8 after invading — discard strategy to advance ---


func test_esc01_003_advances_monster_from_zone_8_after_invading() -> void:
	var card := Real.instance("ESC01-003")
	var state := States.make_state({"p0": {
		"zone_cards": {7: card},
		"hand": [Cards.strategy(2, "S")],
		"monster_zone": 3,
		"has_invaded_this_turn": true,
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(4)
	assert_int(p0.hand.size()).is_equal(0)
	assert_str(str(p0.discard_pile.back().get("id"))).is_equal("S")


func test_esc01_003_silent_without_invasion_or_outside_zone_8() -> void:
	# Monster did not invade this turn: no prompt.
	var card := Real.instance("ESC01-003")
	var state := States.make_state({"p0": {
		"zone_cards": {7: card}, "hand": [Cards.strategy(2, "S")], "monster_zone": 3}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].monster_zone).is_equal(3)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)

	# Entered zone 6 instead of zone 8: no prompt either.
	var card2 := Real.instance("ESC01-003", 1)
	var state2 := States.make_state({"p0": {
		"zone_cards": {5: card2}, "hand": [Cards.strategy(2, "S2")], "monster_zone": 3,
		"has_invaded_this_turn": true}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[0].monster_zone).is_equal(3)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)


func test_esc01_003_skipping_the_discard_does_not_advance() -> void:
	var card := Real.instance("ESC01-003")
	var state := States.make_state({"p0": {
		"zone_cards": {7: card},
		"hand": [Cards.strategy(2, "S")],
		"monster_zone": 3,
		"has_invaded_this_turn": true,
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].monster_zone).is_equal(3)
	assert_int(state.players[0].hand.size()).is_equal(1)


# --- ESC01-004: +5000 CP at rage>=3; destroyed → deck bottom ---


func test_esc01_004_gains_5000_cp_only_with_rage_3() -> void:
	var card := Real.instance("ESC01-004")
	var base: int = card.get("counter_power", 0)
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)

	assert_int(s["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base)
	state.players[0].rage = 2
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base)
	state.players[0].rage = 3
	assert_int(s["effect_handler"].get_effective_zone_cp(0, 2)).is_equal(base + 5000)


func test_esc01_004_destroyed_goes_to_deck_bottom_instead_of_discard() -> void:
	var card := Real.instance("ESC01-004")
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
		.override_failure_message("ESC01-004 should sit at the deck bottom after destruction") \
		.is_equal(str(card.get("id")))


func test_esc01_004_overloaded_goes_to_deck_bottom() -> void:
	# Overload IS <Destroy> (11.5.1) — effect-driven plays over ESC01-004 also
	# send it to the deck bottom instead of the discard.
	var card := Real.instance("ESC01-004")
	var incoming := Cards.battle(3, 2000, "OVER")
	var state := States.make_state({"p0": {
		"hand": [incoming],
		"zone_cards": {5: card},
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.play_battle_card_from_hand(0, incoming, 5)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(5).get("id"))).is_equal("OVER")
	assert_int(p0.discard_pile.size()).is_equal(0)
	assert_str(str(p0.main_deck.back().get("id"))) \
		.override_failure_message("ESC01-004 should sit at the deck bottom after being overloaded") \
		.is_equal(str(card.get("id")))
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)


# --- ESC01-005: when invading with 3+ stacked — reveal top, destroy <= its rank ---


func test_esc01_005_reveals_top_card_and_destroys_lower_rank_battle_card() -> void:
	var card := Real.instance("ESC01-005")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2,
			"main_deck": [Cards.battle(4, 1000, "REV")]},
		"p1": {"zone_cards": {1: Cards.battle(4, 3000, "T4"), 3: Cards.battle(6, 3000, "T6")}},
	})
	for i in range(3):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [], "UNDER-%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_str(str(state.players[0].discard_pile.back().get("id"))).is_equal("REV")
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(3)) \
		.override_failure_message("rank 6 > revealed rank 4 must not be targetable") \
		.is_true()


func test_esc01_005_requires_3_cards_under_the_monster() -> void:
	var card := Real.instance("ESC01-005")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2,
			"main_deck": [Cards.battle(4, 1000, "REV")]},
		"p1": {"zone_cards": {1: Cards.battle(2, 3000, "T2")}},
	})
	for i in range(2):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [], "UNDER-%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


func test_esc01_005_still_mills_when_no_target_qualifies() -> void:
	var card := Real.instance("ESC01-005")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2,
			"main_deck": [Cards.battle(1, 1000, "REV1")]},
		"p1": {"zone_cards": {1: Cards.battle(5, 3000, "T5")}},
	})
	for i in range(3):
		state.players[0].monster_stack.append(Cards.monster(1, 5000, [], "UNDER-%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_str(str(state.players[0].discard_pile.back().get("id"))).is_equal("REV1")
	assert_bool(state.players[1].zone_has_cards(1)).is_true()


# --- ESC01-006: enter may discard whole hand — +1 rage per strategy discarded ---


func test_esc01_006_discards_hand_and_gains_rage_per_strategy() -> void:
	var card := Real.instance("ESC01-006")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"hand": [Cards.strategy(2, "S1"), Cards.strategy(3, "S2"), Cards.battle(2, 2000, "B1")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(3)
	assert_int(p0.rage).is_equal(2)


func test_esc01_006_declining_keeps_hand_and_rage() -> void:
	var card := Real.instance("ESC01-006")
	var state := States.make_state({"p0": {
		"zone_cards": {2: card},
		"hand": [Cards.strategy(2, "S1"), Cards.battle(2, 2000, "B1")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(2)
	assert_int(state.players[0].rage).is_equal(0)


func test_esc01_006_silent_with_empty_hand() -> void:
	var card := Real.instance("ESC01-006")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("choose_option")).is_equal(0)
	assert_int(state.players[0].rage).is_equal(0)


# --- ESD03-005: Godzilla(2026) — +15000 TL w/ rank IV underneath; +15000 TL
# --- Awk8; end phase w/ rage>=3: optional advance 1 ---


func test_esd03_005_threat_bonus_from_rank4_underneath_and_awakening8() -> void:
	var monster := Real.instance("ESD03-005")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 3}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)

	# A rank III under it doesn't count; a rank IV anywhere in the stack does.
	state.players[0].monster_stack.append(Cards.monster(3, 18000, [], "UNDER-R3"))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)
	state.players[0].monster_stack.append(Cards.monster(4, 30000, [], "UNDER-R4"))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(15000)

	state.players[0].monster_zone = 8
	assert_int(handler.get_threat_level_modifier(0)).is_equal(30000)


func test_esd03_005_end_phase_with_3_rage_may_advance() -> void:
	var monster := Real.instance("ESD03-005")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4, "rage": 3}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(state.players[0].monster_zone).is_equal(5)


func test_esd03_005_end_phase_declined_or_low_rage_does_not_advance() -> void:
	var monster := Real.instance("ESD03-005")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4, "rage": 3}})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[0].monster_zone).is_equal(4)

	# Only 2 rage: no prompt at all.
	var monster2 := Real.instance("ESD03-005", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2, "monster_zone": 4, "rage": 2}})
	state2.current_phase = CardEnums.GamePhase.END
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(input2.count_calls("choose_option")).is_equal(0)
	assert_int(state2.players[0].monster_zone).is_equal(4)


# --- ESD03-006: Godzilla(2023) battle — enter: opp rank I monster rage -1;
# --- Overwhelm +3000 CP ---


func test_esd03_006_enter_reduces_rage_only_of_rank1_monster() -> void:
	var card := Real.instance("ESD03-006")
	var state := States.make_state({"p1": {"current_monster": Cards.monster(1), "rage": 2}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)

	var card2 := Real.instance("ESD03-006", 1)
	var state2 := States.make_state({"p1": {"current_monster": Cards.monster(2), "rage": 2}})
	var s2 := _session(state2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(2)


func test_esd03_006_overwhelm_adds_3000_cp() -> void:
	var card := Real.instance("ESD03-006")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 4}, "p1": {"monster_zone": 4}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)
	state.players[1].monster_zone = 5
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(2000)


# --- ESD03-007: Godzilla(2026) battle — Awk6 +3000 CP; Overwhelm + invaded
# --- this turn: play from hand at rank -1 ---


func test_esd03_007_awakening6_adds_3000_cp() -> void:
	var card := Real.instance("ESD03-007")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 5}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)
	state.players[0].monster_zone = 6
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000)


func test_esd03_007_rank_reduced_only_when_invaded_and_overwhelming() -> void:
	var card := Real.instance("ESD03-007")
	var state := States.make_state({
		"p0": {"hand": [card], "monster_zone": 4, "has_invaded_this_turn": true},
		"p1": {"monster_zone": 4},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-1)

	# Behind the opponent's monster: <Overwhelm> is off.
	state.players[1].monster_zone = 5
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)

	# Ahead, but no invasion this turn.
	state.players[1].monster_zone = 3
	state.players[0].has_invaded_this_turn = false
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


# --- ESD04-004: Destoroyah Perfect Form — enter: discard strategy → opp rage -1;
# --- +10000 CP w/ "Godzilla vs. Destoroyah" in play ---


func test_esd04_004_enter_discards_strategy_to_reduce_opponent_rage() -> void:
	var monster := Real.instance("ESD04-004")
	var state := States.make_state({
		"p0": {"current_monster": monster, "hand": [Cards.battle(2, 3000, "BTL"), Cards.strategy(2, "STR")]},
		"p1": {"rage": 2},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_array(input.calls[0]["valid"]).contains_exactly([1])
	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_esd04_004_enter_skip_keeps_opponent_rage() -> void:
	var monster := Real.instance("ESD04-004")
	var state := States.make_state({
		"p0": {"current_monster": monster, "hand": [Cards.strategy(2, "STR")]},
		"p1": {"rage": 2},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_int(state.players[1].rage).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(1)


func test_esd04_004_overwhelm_cp_needs_godzilla_vs_destoroyah_in_play() -> void:
	var monster := Real.instance("ESD04-004")
	var state := States.make_state({"p0": {"current_monster": monster, "strategy_zones": [Cards.strategy(3, "OTHER")]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)

	state.players[0].strategy_zones[1] = Real.instance("EBP04-083")
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(10000)

	# <Overwhelm> is off while our monster is behind the opponent's.
	state.players[1].monster_zone = 3
	state.players[0].monster_zone = 2
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)
	state.players[0].monster_zone = 3
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(10000)


# --- ESD05-002: King Ghidorah(1991) — enter: mill 1, destroy opp battle cards
# --- totalling <= the milled card's rank ---


func test_esd05_002_enter_destroys_within_milled_rank_budget() -> void:
	var monster := Real.instance("ESD05-002")
	var state := States.make_state({
		"p0": {"current_monster": monster, "main_deck": [Cards.battle(5, 3000, "TOP-R5")]},
		"p1": {"zone_cards": {
			0: Cards.battle(3, 3000, "OPP-R3"),
			1: Cards.battle(2, 3000, "OPP-R2"),
			2: Cards.battle(4, 3000, "OPP-R4"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zones": [[0, 1]]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(0)).is_false()
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_str(str(p1.get_zone_top_card(2).get("id"))).is_equal("OPP-R4")
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("TOP-R5")
	# One select/deselect + confirm prompt, budget = the milled card's rank.
	var zones_calls := input.calls.filter(func(c: Dictionary) -> bool: return c["kind"] == "select_zones")
	assert_int(zones_calls.size()).is_equal(1)
	assert_array(zones_calls[0]["valid"]).contains_exactly([0, 1, 2])
	assert_dict(zones_calls[0]["constraints"]).is_equal({"weights": {0: 3, 1: 2, 2: 4}, "budget": 5})


func test_esd05_002_empty_deck_destroys_nothing() -> void:
	var monster := Real.instance("ESD05-002")
	var state := States.make_state({
		"p0": {"current_monster": monster},
		"p1": {"zone_cards": {0: Cards.battle(1, 3000, "OPP-R1")}},
	})
	state.players[0].main_deck.clear()
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_int(input.count_calls("select_zones")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(0)).is_true()


# --- ESD03-008: Humanity's Crime and Punishment — monster rank III+: each
# --- player keeps 1 battle card (owner first), rest destroyed; rage 3+:
# --- opponent discards to 2 ---


func test_esd03_008_each_player_keeps_one_owner_first_then_opponent_discards_to_2() -> void:
	var card := Real.instance("ESD03-008")
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(3), "rage": 3, "zone_cards": {
			1: Cards.battle(2, 2000, "OWN-A"), 4: Cards.battle(2, 2000, "OWN-B"),
		}},
		"p1": {"hand": [Cards.battle(), Cards.battle(), Cards.battle(), Cards.battle()], "zone_cards": {
			0: Cards.battle(2, 2000, "OPP-A"), 3: Cards.battle(2, 2000, "OPP-B"), 6: Cards.battle(2, 2000, "OPP-C"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4, 3]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	# Owner is asked first (own board), then the opponent (their board).
	var zone_calls := input.calls.filter(func(c: Dictionary) -> bool: return c["kind"] == "select_zone")
	assert_int(zone_calls[0]["player_id"]).is_equal(0)
	assert_int(zone_calls[0]["target"]).is_equal(0)
	assert_int(zone_calls[1]["player_id"]).is_equal(1)
	assert_int(zone_calls[1]["target"]).is_equal(1)
	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([4])
	assert_array(state.players[1].get_battle_card_zone_indices()).contains_exactly([3])
	assert_int(state.players[1].hand.size()).is_equal(2)

	# No modal: the picks are made public by highlight + log only.
	assert_int(input.count_calls("acknowledge_reveal")).is_equal(0)


func test_esd03_008_kept_zones_stay_highlighted_until_destruction() -> void:
	var card := Real.instance("ESD03-008")
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(3), "zone_cards": {
			1: Cards.battle(2, 2000, "OWN-A"), 4: Cards.battle(2, 2000, "OWN-B"),
		}},
		"p1": {"zone_cards": {
			0: Cards.battle(2, 2000, "OPP-A"), 3: Cards.battle(2, 2000, "OPP-B"),
		}},
	})
	var input := _HighlightAwareInput.new()
	input.answers = {"select_zone": [4, 3]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	var lit: Dictionary = {}  # "pid:zone" -> true while highlighted
	handler.effect_zone_highlighted.connect(func(pid: int, z: int) -> void: lit["%d:%d" % [pid, z]] = true)
	handler.effect_zone_unhighlighted.connect(func(pid: int, z: int) -> void: lit.erase("%d:%d" % [pid, z]))
	input.lit = lit

	await handler.trigger_enter(0, card)

	# While the opponent chose, the owner's kept zone was already highlighted.
	assert_array(input.lit_at_prompt[1]).contains_exactly(["0:4"])
	# After the effect resolves every highlight is cleared.
	assert_dict(lit).is_empty()


func test_esd03_008_low_rank_monster_and_low_rage_do_nothing() -> void:
	var card := Real.instance("ESD03-008")
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(2), "rage": 2},
		"p1": {"hand": [Cards.battle(), Cards.battle(), Cards.battle()], "zone_cards": {
			0: Cards.battle(2, 2000, "OPP-A"), 3: Cards.battle(2, 2000, "OPP-B"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_int(state.players[1].get_battle_card_zone_indices().size()).is_equal(2)
	assert_int(state.players[1].hand.size()).is_equal(3)


func test_esd03_008_single_battle_card_is_kept_without_prompt() -> void:
	var card := Real.instance("ESD03-008")
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(4)},
		"p1": {"zone_cards": {5: Cards.battle(2, 2000, "OPP-ONLY")}},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("select_zone")).is_equal(0)
	assert_bool(state.players[1].zone_has_cards(5)).is_true()


func test_esd03_008_logs_each_kept_zone() -> void:
	var card := Real.instance("ESD03-008")
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(3), "zone_cards": {2: Cards.battle(2, 2000, "OWN")}},
		"p1": {"zone_cards": {6: Cards.battle(2, 2000, "OPP")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	var tokens: Array = []
	handler.log_message.connect(func(t: Dictionary) -> void: tokens.append(t))

	await handler.trigger_enter(0, card)

	var chose := tokens.filter(func(t: Dictionary) -> bool: return t.get("type") == "effect_chose_zone")
	assert_int(chose.size()).is_equal(2)
	assert_int(chose[0]["player_id"]).is_equal(0)
	assert_int(chose[0]["zone"]).is_equal(2)
	assert_str(str(chose[0]["card_id"])).is_equal("OWN")
	assert_int(chose[1]["player_id"]).is_equal(1)
	assert_int(chose[1]["zone"]).is_equal(6)
	assert_str(str(GameLog.render(chose[1]))).contains("OPP")


## Snapshots which zones are highlighted each time a zone is asked for.
class _HighlightAwareInput extends ScriptedPlayerInput:
	var lit: Dictionary = {}
	var lit_at_prompt: Array = []

	func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
		lit_at_prompt.append(lit.keys())
		return super(player_id, target_player_id, valid_zones, prompt, allow_skip)
