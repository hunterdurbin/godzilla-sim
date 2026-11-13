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


# --- ESD03-001: Godzilla(2026) — invading by discarding a monster card:
# --- rage +1 per zone invaded ---


func _esd03_001_invade(cost: Dictionary) -> GameState:
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD03-001"),
		"hand": [cost],
		"monster_zone": 1,
	}})
	var s := _session(state)
	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)
	return state


func test_esd03_001_monster_discard_gains_rage_per_zone() -> void:
	var state := await _esd03_001_invade(Cards.monster(2, 8000, [], "COST-M1", 1))
	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(state.players[0].rage).is_equal(1)

	# Invade 2 → activates twice.
	var state2 := await _esd03_001_invade(Cards.monster(2, 8000, [], "COST-M2", 2))
	assert_int(state2.players[0].monster_zone).is_equal(3)
	assert_int(state2.players[0].rage).is_equal(2)


func test_esd03_001_battle_discard_gains_no_rage() -> void:
	var state := await _esd03_001_invade(Cards.battle(1, 5000, "COST-B", [], 2))
	assert_int(state.players[0].monster_zone).is_equal(3)
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
# --- Dominate +3000 CP ---


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


func test_esd03_006_dominate_adds_3000_cp() -> void:
	var card := Real.instance("ESD03-006")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 4}, "p1": {"monster_zone": 4}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)
	state.players[1].monster_zone = 5
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(2000)


# --- ESD03-007: Godzilla(2026) battle — Awk6 +3000 CP; Dominate + invaded
# --- this turn: play from hand at rank -1 ---


func test_esd03_007_awakening6_adds_3000_cp() -> void:
	var card := Real.instance("ESD03-007")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 5}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(5000)
	state.players[0].monster_zone = 6
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(8000)


func test_esd03_007_rank_reduced_only_when_invaded_and_dominating() -> void:
	var card := Real.instance("ESD03-007")
	var state := States.make_state({
		"p0": {"hand": [card], "monster_zone": 4, "has_invaded_this_turn": true},
		"p1": {"monster_zone": 4},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-1)

	# Behind the opponent's monster: <Dominate> is off.
	state.players[1].monster_zone = 5
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)

	# Ahead, but no invasion this turn.
	state.players[1].monster_zone = 3
	state.players[0].has_invaded_this_turn = false
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


# --- ESD04-002: Destoroyah Aggregate Form — when invading: evolve a rank ≤6
# --- Evolution battle card (per zone invaded) ---


func _esd04_002_evo(rank: int, id: String) -> Dictionary:
	var c := Cards.battle(rank, 3000, id, [CardEnums.CardTrait.DESTOROYAH])
	c["evolution_rank"] = 7
	c["evolution_trait"] = CardEnums.CardTrait.DESTOROYAH
	return c


func _esd04_002_invade(state: GameState, input: ScriptedPlayerInput) -> void:
	var s := States.make_session(state, input)
	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)


func test_esd04_002_invading_evolves_rank6_or_lower_card() -> void:
	var low := _esd04_002_evo(6, "EVO-R6")
	var high := _esd04_002_evo(7, "EVO-R7")
	var target := Cards.battle(7, 9000, "DEST-R7", [CardEnums.CardTrait.DESTOROYAH])
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-002"),
		"hand": [Cards.battle(1, 2000, "COST", [], 1)],
		"monster_zone": 1,
		"zone_cards": {2: low, 4: high},
		"main_deck": [Cards.battle(1, 2000, "FILLER"), target],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [2], "search_cards": [{"id": "DEST-R7"}]}

	await _esd04_002_invade(state, input)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(2)
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal("DEST-R7")
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# Only the rank ≤6 Evolution card was offered.
	assert_that(input.calls[0]["valid"]).is_equal([2])


func test_esd04_002_invade_2_evolves_twice() -> void:
	var a := _esd04_002_evo(2, "EVO-A")
	var b := _esd04_002_evo(3, "EVO-B")
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-002"),
		"hand": [Cards.battle(1, 2000, "COST", [], 2)],
		"monster_zone": 1,
		"zone_cards": {4: a, 6: b},
		"main_deck": [
			Cards.battle(6, 9000, "TOP-1", [CardEnums.CardTrait.DESTOROYAH]),
			Cards.battle(6, 9000, "TOP-2", [CardEnums.CardTrait.DESTOROYAH]),
		],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [4, 6], "search_cards": [{"id": "TOP-1"}, {"id": "TOP-2"}]}

	await _esd04_002_invade(state, input)

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(3)
	assert_int(input.count_calls("select_zone")).is_equal(2)
	assert_array([str(p0.get_zone_top_card(4).get("id")), str(p0.get_zone_top_card(6).get("id")),
		p0.get_zone_stack(4).size(), p0.get_zone_stack(6).size()]).is_equal(["TOP-1", "TOP-2", 2, 2])


func test_esd04_002_covered_evolution_enter_still_resolves() -> void:
	# Match repro: invade 2 → evolve EBP01-049 into EBP01-054 (054's Enter goes
	# to standby) → second activation evolves 054 itself. 054 is now covered,
	# but its Enter already triggered and still resolves (10.5.2.3.3 / 10.6.7).
	var aggregate := Real.instance("EBP01-049")
	var flying := Real.instance("EBP01-054")
	var r8 := Cards.battle(8, 9000, "DEST-R8", [CardEnums.CardTrait.DESTOROYAH])
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-002"),
		"hand": [Cards.battle(1, 2000, "COST", [], 2)],
		"monster_zone": 1,
		"zone_cards": {4: aggregate},
		"main_deck": [Cards.battle(1, 1000, "D1"), Cards.battle(1, 1000, "D2"), flying, r8],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {
		"select_zone": [4, 4],
		"search_cards": [{"id": flying.get("id")}, {"id": "DEST-R8"}],
	}
	var s := States.make_session(state, input)
	var stack_labels: Array = []
	s["effect_handler"].events = s["events"]
	s["events"].effect_stack_changed.connect(func(rows: Array) -> void:
		for r in rows:
			stack_labels.append(str(r.get("label", ""))))

	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal("DEST-R8")
	assert_int(p0.get_zone_stack(4).size()).is_equal(3)
	# 054's Enter resolved: drew D1+D2, then discarded 2.
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(3)  # COST + 2 discards
	# While covered, the pending row still names its zone.
	assert_bool(stack_labels.has(str(flying.get("name")) + " (Zone 5, covered)")).is_true()


func test_esd04_002_silent_without_eligible_card() -> void:
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-002"),
		"hand": [Cards.battle(1, 2000, "COST", [], 1)],
		"monster_zone": 1,
		"zone_cards": {2: _esd04_002_evo(7, "EVO-R7"), 4: Cards.battle(3, 3000, "NO-EVO")},
	}})
	var input := ScriptedPlayerInput.new()

	await _esd04_002_invade(state, input)

	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(input.count_calls("select_zone")).is_equal(0)


# --- ESD04-003: Destoroyah Flying Form — enter: return "Godzilla vs. Destoroyah"
# --- from discard; when invading: Destoroyah battle card discard → deck bottom ---


func test_esd04_003_enter_returns_godzilla_vs_destoroyah_from_discard() -> void:
	var monster := Real.instance("ESD04-003")
	var gvd := Real.instance("EBP04-083")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var p0 := state.players[0]
	p0.discard_pile = [Cards.strategy(3, "OTHER"), gvd]
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": gvd.get("id")}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)

	assert_int(input.calls[0]["matching"].size()).is_equal(1)
	assert_array(p0.hand.map(func(c: Dictionary) -> String: return str(c.get("id")))).contains_exactly([gvd.get("id")])
	assert_int(p0.discard_pile.size()).is_equal(1)


func test_esd04_003_enter_may_skip_and_is_silent_without_target() -> void:
	var monster := Real.instance("ESD04-003")
	var state := States.make_state({"p0": {"current_monster": monster}})
	var p0 := state.players[0]
	p0.discard_pile = [Real.instance("EBP04-083")]
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(p0.hand.size()).is_equal(0)
	assert_int(p0.discard_pile.size()).is_equal(1)

	p0.discard_pile = [Cards.strategy(3, "OTHER")]
	await s["effect_handler"].trigger_enter(0, monster)
	assert_int(input.count_calls("search_cards")).is_equal(1)


func test_esd04_003_invading_places_destoroyah_battle_card_on_deck_bottom() -> void:
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-003"),
		"hand": [Cards.battle(1, 2000, "COST", [], 1)],
		"monster_zone": 1,
		"main_deck": [Cards.battle(1, 1000, "DECK-TOP")],
	}})
	var p0 := state.players[0]
	p0.discard_pile = [
		Cards.battle(4, 4000, "DEST-A", [CardEnums.CardTrait.DESTOROYAH]),
		Cards.battle(4, 4000, "PLAIN"),
		Cards.monster(2, 10000, [CardEnums.CardTrait.DESTOROYAH], "DEST-MON"),
	]
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DEST-A"}]}

	await _esd04_002_invade(state, input)

	assert_int(p0.monster_zone).is_equal(2)
	# Only the Destoroyah battle card is offered (not the monster card).
	assert_int(input.calls[0]["matching"].size()).is_equal(1)
	assert_str(str(p0.main_deck.back().get("id"))).is_equal("DEST-A")
	assert_bool(p0.discard_pile.any(func(c: Dictionary) -> bool: return c.get("id") == "DEST-A")).is_false()


func test_esd04_003_invade_2_places_twice() -> void:
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-003"),
		"hand": [Cards.battle(1, 2000, "COST", [], 2)],
		"monster_zone": 1,
	}})
	var p0 := state.players[0]
	p0.discard_pile = [
		Cards.battle(4, 4000, "DEST-A", [CardEnums.CardTrait.DESTOROYAH]),
		Cards.battle(5, 5000, "DEST-B", [CardEnums.CardTrait.DESTOROYAH]),
	]
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "DEST-B"}, {"id": "DEST-A"}]}

	await _esd04_002_invade(state, input)

	assert_int(p0.monster_zone).is_equal(3)
	assert_int(input.count_calls("search_cards")).is_equal(2)
	assert_array(p0.main_deck.map(func(c: Dictionary) -> String: return str(c.get("id")))).is_equal(["DEST-B", "DEST-A"])


func test_esd04_003_invading_silent_without_destoroyah_battle_card() -> void:
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("ESD04-003"),
		"hand": [Cards.battle(1, 2000, "COST", [], 1)],
		"monster_zone": 1,
	}})
	state.players[0].discard_pile = [Cards.battle(4, 4000, "PLAIN")]
	var input := ScriptedPlayerInput.new()

	await _esd04_002_invade(state, input)

	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(input.count_calls("search_cards")).is_equal(0)


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


func test_esd04_004_dominate_cp_needs_godzilla_vs_destoroyah_in_play() -> void:
	var monster := Real.instance("ESD04-004")
	var state := States.make_state({"p0": {"current_monster": monster, "strategy_zones": [Cards.strategy(3, "OTHER")]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(0)

	state.players[0].strategy_zones[1] = Real.instance("EBP04-083")
	assert_int(handler.get_monster_cp_modifier(0)).is_equal(10000)

	# <Dominate> is off while our monster is behind the opponent's.
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


# --- ESD04-001: Destoroyah Juvenile Form — Dominate, end start: battle card
# --- from hand → deck bottom, draw 1 ---


func test_esd04_001_end_phase_puts_battle_card_on_deck_bottom_and_draws() -> void:
	var monster := Real.instance("ESD04-001")
	var state := States.make_state({
		"p0": {
			"current_monster": monster, "monster_zone": 3,
			"hand": [Cards.strategy(2, "STR"), Cards.battle(2, 3000, "BTL")],
			"main_deck": [Cards.battle(1, 1000, "TOP"), Cards.battle(1, 1000, "NEXT")],
		},
		"p1": {"monster_zone": 3},
	})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var logs: Array = []
	s["effect_handler"].log_message.connect(func(entry: Dictionary) -> void: logs.append(entry))

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)

	var p0 := state.players[0]
	assert_array(input.calls[0]["valid"]).contains_exactly([1])
	assert_str(str(p0.main_deck.back().get("id"))).is_equal("BTL")
	assert_array(p0.hand.map(func(c: Dictionary) -> String: return str(c.get("id")))) \
		.contains_exactly(["STR", "TOP"])
	assert_int(p0.discard_pile.size()).is_equal(0)
	# The reveal is public via the log line naming the card.
	var bottom_logs := logs.filter(func(e: Dictionary) -> bool: return e.get("type") == "effect_put_card_on_bottom_of_deck")
	assert_int(bottom_logs.size()).is_equal(1)
	assert_str(str(bottom_logs[0].get("card_id"))).is_equal("BTL")


func test_esd04_001_skip_or_no_dominate_does_nothing() -> void:
	var monster := Real.instance("ESD04-001")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 3, "hand": [Cards.battle(2, 3000, "BTL")],
			"main_deck": [Cards.battle(1, 1000, "TOP")]},
		"p1": {"monster_zone": 2},
	})
	state.current_phase = CardEnums.GamePhase.END
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].main_deck.size()).is_equal(1)

	# Behind the opponent's monster: <Dominate> is off — no prompt.
	var monster2 := Real.instance("ESD04-001", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": monster2, "monster_zone": 2, "hand": [Cards.battle(2, 3000, "BTL")]},
		"p1": {"monster_zone": 3},
	})
	state2.current_phase = CardEnums.GamePhase.END
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)
	assert_int(state2.players[0].hand.size()).is_equal(1)


# --- ESD04-006: Godzilla vs. Destoroyah — opp turn: +5000 TL per Destoroyah
# --- battle card in your zones (stacks count once) ---


func test_esd04_006_opponent_turn_threat_per_destoroyah_battle_card() -> void:
	var gvd := Real.instance("ESD04-006")
	var destoroyah := [CardEnums.CardTrait.DESTOROYAH]
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"strategy_zones": [gvd], "zone_cards": {
			0: Cards.battle(2, 3000, "DES-A", destoroyah),
			3: Cards.battle(3, 3000, "DES-B", destoroyah),
			5: Cards.battle(2, 3000, "OTHER"),
		}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_threat_level_modifier(0)).is_equal(10000)

	# An evolution stack counts as 1 card.
	state.players[0].get_zone_stack(3).append(Cards.battle(2, 3000, "DES-UNDER", destoroyah))
	assert_int(handler.get_threat_level_modifier(0)).is_equal(10000)

	# Your own turn: no bonus.
	state.current_player_id = 0
	assert_int(handler.get_threat_level_modifier(0)).is_equal(0)


func test_esd04_006_enables_esd04_004_dominate_cp() -> void:
	var monster := Real.instance("ESD04-004")
	var state := States.make_state({"p0": {"current_monster": monster, "strategy_zones": [Real.instance("ESD04-006")]}})
	var s := _session(state)
	assert_int(s["effect_handler"].get_monster_cp_modifier(0)).is_equal(10000)


# --- ESD05-001: King Ghidorah(1991) — enter: mill = monster's zone number ---


func _esd05_001_enter(monster_zone: int, deck_size: int) -> GameState:
	var card := Real.instance("ESD05-001")
	var deck: Array = []
	for i in range(deck_size):
		deck.append(Cards.battle(1, 1000, "D%d" % i))
	var state := States.make_state({"p0": {
		"current_monster": card, "monster_zone": monster_zone, "main_deck": deck,
	}})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	return state


func test_esd05_001_enter_mills_zone_number() -> void:
	var state := await _esd05_001_enter(3, 6)
	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_int(state.players[0].main_deck.size()).is_equal(3)

	var state2 := await _esd05_001_enter(6, 8)
	assert_int(state2.players[0].discard_pile.size()).is_equal(6)


func test_esd05_001_enter_mills_only_what_the_deck_has() -> void:
	var state := await _esd05_001_enter(5, 2)
	assert_int(state.players[0].discard_pile.size()).is_equal(2)
	assert_int(state.players[0].main_deck.size()).is_equal(0)


# --- ESD05-003: Dorat — Dominate enter: mill 3 ---


func test_esd05_003_dominate_enter_mills_3() -> void:
	var card := Real.instance("ESD05-003")
	var deck: Array = []
	for i in range(4):
		deck.append(Cards.battle(1, 1000, "D%d" % i))
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "monster_zone": 3, "main_deck": deck},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_int(state.players[0].main_deck.size()).is_equal(1)


func test_esd05_003_no_dominate_does_not_mill() -> void:
	var card := Real.instance("ESD05-003")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "monster_zone": 2, "main_deck": [Cards.battle(), Cards.battle(), Cards.battle()]},
		"p1": {"monster_zone": 3},
	})
	var s := _session(state)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(3)


# --- ESD05-004: Godzillasaurus — card under your monster: +3000 CP ---


func test_esd05_004_gains_3000_cp_with_card_under_monster() -> void:
	var card := Real.instance("ESD05-004")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(3000)
	state.players[0].monster_stack.append(Cards.monster(1, 5000, [], "UNDER"))
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(6000)


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


# --- ESD03-002: Godzilla(2026) rank II — enter: destroy every rank ≤3 battle
# --- card on both boards ---


func test_esd03_002_enter_destroys_rank_3_or_lower_on_both_boards() -> void:
	var card := Real.instance("ESD03-002")
	var state := States.make_state({
		"p0": {"current_monster": card, "zone_cards": {
			1: Cards.battle(3, 2000, "OWN-R3"), 4: Cards.battle(4, 3000, "OWN-R4"),
		}},
		"p1": {"zone_cards": {
			0: Cards.battle(1, 2000, "OPP-R1"), 3: Cards.battle(6, 5000, "OPP-R6"),
		}},
	})
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, card)

	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([4])
	assert_array(state.players[1].get_battle_card_zone_indices()).contains_exactly([3])
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


# --- ESD03-003: Godzilla(2026) rank III — enter: reveal top, monster → hand
# --- else discard; opp turn Dominate counter start: destroy opp rank ≤6 in
# --- column ---


func test_esd03_003_enter_reveals_top_card(top_is_monster: bool, hand_size: int, discard_size: int,
		_test_parameters := [
			[true, 1, 0],
			[false, 0, 1],
		]) -> void:
	var card := Real.instance("ESD03-003")
	var top := Cards.monster(2, 9000, [], "TOP-MON") if top_is_monster else Cards.battle(2, 3000, "TOP-BTL")
	var state := States.make_state({
		"p0": {"current_monster": card, "main_deck": [top, Cards.battle(1, 2000, "DECK-2")]},
	})
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(hand_size)
	assert_int(state.players[0].discard_pile.size()).is_equal(discard_size)


func test_esd03_003_enter_with_empty_deck_does_nothing() -> void:
	var card := Real.instance("ESD03-003")
	var state := States.make_state({"p0": {"current_monster": card}})
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_esd03_003_dominate_counter_start_destroys_rank_6_or_lower_in_column(opp_monster_zone: int, destroyed: bool,
		_test_parameters := [
			[3, true],   # same zone → Dominate on
			[1, true],   # ahead → Dominate on
			[5, false],  # behind → Dominate off
		]) -> void:
	var card := Real.instance("ESD03-003")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "monster_zone": 3},  # anchor idx 2 → opp column zones [2, 7]
		"p1": {"monster_zone": opp_monster_zone, "zone_cards": {
			2: Cards.battle(6, 5000, "OPP-R6"), 7: Cards.battle(7, 6000, "OPP-R7"),
		}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[1].zone_has_cards(2)) \
		.override_failure_message("ESD03-003: rank 6 in column destroyed iff Dominate").is_equal(not destroyed)
	assert_bool(state.players[1].zone_has_cards(7)) \
		.override_failure_message("ESD03-003: rank 7 must survive the rank<=6 cap").is_true()


func test_esd03_003_does_not_fire_on_own_counter_phase() -> void:
	var card := Real.instance("ESD03-003")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 3},
		"p1": {"zone_cards": {2: Cards.battle(6, 5000, "OPP-R6")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[1].zone_has_cards(2)).is_true()


# --- ESD05-005: Constructed Future — owner marks own battle cards lowest rank
# --- first (multi-zone prompt); if 3 are truly destroyed, play a highest-rank
# --- battle card from discard; "when destroyed" triggers resolve last ---

const _INDESTRUCTIBLE := "res://tests/fixtures/effects/indestructible_effect.gd"


func _cf_session(zone_cards: Dictionary, discard: Array = [], answers: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var p0: Dictionary = {"zone_cards": zone_cards}
	p0.merge(opts.get("p0", {}))
	var state := States.make_state({
		"current_player_id": opts.get("current_player_id", 0),
		"p0": p0,
		"p1": opts.get("p1", {}),
	})
	for c in discard:
		state.players[0].discard_pile.append(c)
	var input := ScriptedPlayerInput.new()
	input.answers = answers
	var s := States.make_session(state, input)
	s["state"] = state
	s["input"] = input
	return s


func _calls(input: ScriptedPlayerInput, kind: String) -> Array:
	return input.calls.filter(func(c: Dictionary) -> bool: return c["kind"] == kind)


func _indestructible(rank: int, id: String) -> Dictionary:
	var c := Cards.battle(rank, 2000, id)
	c["effect_script"] = _INDESTRUCTIBLE
	return c


func _crystal() -> Dictionary:
	var token := Real.instance("EBP02-T03")
	token["id"] = "EBP02-T03"  # bare template id, as the engine creates tokens
	return token


# 1. Normal: ranks 1,1,2,2,5 — one multi-zone prompt, lowest-first rule,
#    owner breaks the rank-2 tie, highest-rank discard card is played.
func test_esd05_005_marks_three_lowest_first_then_plays_highest() -> void:
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1A"), 1: Cards.battle(1, 2000, "R1B"),
		3: Cards.battle(2, 2000, "R2A"), 4: Cards.battle(2, 2000, "R2B"),
		5: Cards.battle(5, 3000, "R5"),
	}, [Cards.battle(7, 6000, "DISCARD-R7"), Cards.strategy(9, "DISCARD-STR9")],
		{"select_zones": [[0, 1, 4]], "select_zone": [6]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	var prompt: Dictionary = _calls(s["input"], "select_zones")[0]
	assert_int(prompt["player_id"]).is_equal(0)
	assert_int(prompt["target"]).is_equal(0)
	assert_array(prompt["valid"]).contains_exactly_in_any_order([0, 1, 3, 4, 5])
	assert_int(prompt["count"]).is_equal(3)
	assert_bool(prompt["up_to"]).is_false()
	assert_dict(prompt["constraints"]).is_equal(
		{"weights": {0: 1, 1: 1, 3: 2, 4: 2, 5: 5}, "lowest_first": true})
	# Only the battle card is offered for the play-back (strategy ignored).
	var search: Dictionary = _calls(s["input"], "search_cards")[0]
	assert_int(search["matching"].size()).is_equal(1)
	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([3, 5, 6])
	assert_str(str(state.players[0].get_zone_top_card(6).get("id"))).is_equal("DISCARD-R7")


# 2. Lowest-first rule + undo cascade (UI deselect uses prune).
func test_esd05_005_lowest_first_rule_unlocks_tiers_and_undo_relocks() -> void:
	var c := ZoneSelectConstraints.lowest_first({0: 1, 1: 1, 3: 2, 4: 2, 5: 5})
	# Rank 2s locked until both rank 1s are marked.
	assert_bool(ZoneSelectConstraints.can_add(c, [], 3)).is_false()
	assert_bool(ZoneSelectConstraints.can_add(c, [0], 3)).is_false()
	assert_bool(ZoneSelectConstraints.can_add(c, [0, 1], 3)).is_true()
	assert_bool(ZoneSelectConstraints.can_add(c, [0, 1], 4)).is_true()
	assert_bool(ZoneSelectConstraints.can_add(c, [0, 1], 5)).is_false()
	# Unmarking a rank 1 while a rank 2 is marked drops the rank 2 too.
	assert_array(ZoneSelectConstraints.prune(c, [1, 3])).contains_exactly([1])
	assert_array(ZoneSelectConstraints.prune(c, [0, 1, 3])).contains_exactly([0, 1, 3])
	assert_array(ZoneSelectConstraints.prune(c, [3, 4])).is_empty()


# 3. Exactly 3, no ties: still prompts, all 3 must be marked.
func test_esd05_005_forced_three_still_prompts() -> void:
	var s := _cf_session({0: Cards.battle(1, 2000, "A"), 2: Cards.battle(3, 2000, "B"), 4: Cards.battle(6, 2000, "C")},
		[], {"select_zone": [7]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	var prompts := _calls(s["input"], "select_zones")
	assert_int(prompts.size()).is_equal(1)
	assert_int(prompts[0]["count"]).is_equal(3)
	# All destroyed; the R6 it just destroyed is the highest → played back.
	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([7])
	assert_str(str(state.players[0].get_zone_top_card(7).get("id"))).is_equal("C")


# 4. Fewer than 3: mark all, all destroyed, nothing played.
func test_esd05_005_fewer_than_three_marks_all_and_plays_nothing(n: int,
		_test_parameters := [[1], [2]]) -> void:
	var zones := {}
	for i in range(n):
		zones[i] = Cards.battle(i + 1, 2000, "OWN-%d" % i)
	var s := _cf_session(zones, [Cards.battle(7, 6000, "DISCARD-R7")])
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_int(_calls(s["input"], "select_zones")[0]["count"]).is_equal(n)
	assert_int(state.players[0].get_battle_card_zone_indices().size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(n + 1)
	assert_int(s["input"].count_calls("search_cards")).is_equal(0)


func test_esd05_005_no_battle_cards_does_nothing() -> void:
	var s := _cf_session({}, [Cards.battle(7, 6000, "DISCARD-R7")])

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_int(s["input"].count_calls("select_zones")).is_equal(0)
	assert_int(s["input"].count_calls("search_cards")).is_equal(0)


# 5. Protected card is the lowest: it must be marked, survives, no play-back.
func test_esd05_005_protected_lowest_card_spends_a_slot_and_blocks_play() -> void:
	var s := _cf_session({
		0: _indestructible(1, "PROT-R1"), 1: Cards.battle(2, 2000, "R2"),
		2: Cards.battle(3, 2000, "R3"), 3: Cards.battle(4, 2000, "R4"),
	}, [Cards.battle(7, 6000, "DISCARD-R7")])
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	# Protected card is in the prompt and in the ordering.
	var prompt: Dictionary = _calls(s["input"], "select_zones")[0]
	assert_array(prompt["valid"]).contains(0)
	assert_bool(ZoneSelectConstraints.can_add(prompt["constraints"], [], 1)).is_false()
	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([0, 3])
	assert_int(s["input"].count_calls("search_cards")).is_equal(0)


# 6. Protected card above the cutoff: never markable; 3 destroyed, play-back.
func test_esd05_005_protected_card_above_cutoff_is_never_markable() -> void:
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"),
		2: Cards.battle(3, 2000, "R3"), 3: _indestructible(5, "PROT-R5"),
	}, [Cards.battle(7, 6000, "DISCARD-R7")], {"select_zone": [6]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	var c: Dictionary = _calls(s["input"], "select_zones")[0]["constraints"]
	for picked: Array in [[], [0], [0, 1]]:
		assert_bool(ZoneSelectConstraints.can_add(c, picked, 3)).is_false()
	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([3, 6])
	assert_str(str(state.players[0].get_zone_top_card(6).get("id"))).is_equal("DISCARD-R7")


# 7. Replacement (ESD01-011 → deck bottom) among the 3: not destroyed, no play.
func test_esd05_005_replaced_destruction_does_not_count() -> void:
	var replacer := Real.instance("ESD01-011")  # rank 5, "place on bottom instead"
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"),
		2: replacer, 3: Cards.battle(7, 6000, "R7"),
	}, [Cards.battle(8, 8000, "DISCARD-R8")])
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([3])
	assert_str(str(state.players[0].main_deck.back().get("id"))).is_equal(str(replacer["id"]))
	assert_int(s["input"].count_calls("search_cards")).is_equal(0)


# 8. Crystal tokens count as destroyed (banished, not discarded).
func test_esd05_005_crystal_tokens_count_toward_three() -> void:
	var s := _cf_session({
		0: _crystal(), 1: _crystal(), 2: Cards.battle(3, 2000, "R3"), 3: Cards.battle(7, 6000, "R7"),
	}, [Cards.battle(5, 4000, "DISCARD-R5")], {"select_zone": [6]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([3, 6])
	assert_str(str(state.players[0].get_zone_top_card(6).get("id"))).is_equal("DISCARD-R5")
	# Tokens never reach the discard pile; R3 does.
	var ids: Array = state.players[0].discard_pile.map(func(c: Dictionary) -> String: return str(c["id"]))
	assert_array(ids).contains_exactly(["R3"])


# 12. Three tokens destroyed → 3 destroyed but no battle card in discard.
func test_esd05_005_three_tokens_with_empty_discard_plays_nothing() -> void:
	var s := _cf_session({0: _crystal(), 1: _crystal(), 2: _crystal(), 3: Cards.battle(7, 6000, "R7")})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_array(state.players[0].get_battle_card_zone_indices()).contains_exactly([3])
	assert_int(s["input"].count_calls("search_cards")).is_equal(0)


# 9. Ordering uses effective field rank (opponent's EBP03-025: −1 on its turn).
func test_esd05_005_ordering_uses_effective_field_rank() -> void:
	var s := _cf_session({0: Cards.battle(3, 2000, "R3"), 1: Cards.battle(1, 2000, "R1")}, [],
		{}, {"current_player_id": 1, "p1": {"current_monster": Real.instance("EBP03-025")}})

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_dict(_calls(s["input"], "select_zones")[0]["constraints"]["weights"]).is_equal({0: 2, 1: 0})


# 10. Just-destroyed card is the highest and is played back; its batch-mate's
#     Revenge (EBP02-058) resolves AFTER the play-back.
func test_esd05_005_revenge_resolves_after_play_back() -> void:
	var dorat := Real.instance("EBP02-058")  # rank 2, Revenge: return a KG monster
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: dorat, 2: Cards.battle(6, 5000, "R6"),
	}, [Cards.monster(3, 19000, [CardEnums.CardTrait.KING_GHIDORAH], "KG-MON")],
		{"select_zone": [7]})
	var state: GameState = s["state"]
	var handler: EffectHandler = s["effect_handler"]
	var order: Array[String] = []
	handler.log_message.connect(func(t: Dictionary) -> void:
		if t.get("type") == "revenge_triggered":
			order.append("revenge"))
	state.players[0].zones_changed.connect(func() -> void:
		if state.players[0].get_zone_top_card(7).get("id", "") == "R6" and not order.has("play"):
			order.append("play"))

	await handler.trigger_enter(0, Real.instance("ESD05-005"))

	assert_str(str(state.players[0].get_zone_top_card(7).get("id"))).is_equal("R6")
	assert_array(order).contains_exactly(["play", "revenge"])
	var searches := _calls(s["input"], "search_cards")
	assert_int(searches.size()).is_equal(2)
	assert_str(str(searches[0]["prompt"])).is_equal(tr("STR_EFF_ESD05_005_PLAY_PROMPT"))


# 10b. Opponent's "whenever destroyed" watcher (EBP04-002: column destroy →
#      we discard to 2) is a trigger, not a replacement: it waits until the
#      whole effect — play-back included — has resolved.
func test_esd05_005_opponent_destroy_watcher_resolves_after_play_back() -> void:
	var hand: Array = []
	for i in range(4):
		hand.append(Cards.battle(1, 1000, "HAND-%d" % i))
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"), 2: Cards.battle(3, 2000, "R3-COL"),
	}, [Cards.battle(7, 6000, "DISCARD-R7")], {"select_zone": [6]}, {
		"p0": {"hand": hand},
		# Opp monster zone 3 → anchor idx 2 → our column zones [2, 7].
		"p1": {"current_monster": Real.instance("EBP04-002"), "monster_zone": 3,
			"strategy_zones": [Cards.strategy(1, "OPP-STR1")]},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	var kinds: Array = input.calls.map(func(c: Dictionary) -> String: return c["kind"])
	assert_int(kinds.find("search_cards")).is_less(kinds.find("choose_hand_discards"))
	assert_int(kinds.find("select_zone")).is_less(kinds.find("choose_hand_discards"))
	assert_str(str(state.players[0].get_zone_top_card(6).get("id"))).is_equal("DISCARD-R7")
	assert_int(state.players[0].hand.size()).is_equal(2)


# 10c. Godzilla Earth's link (EBP04-067) is an automatic ability: destroying
#      its token doesn't pull Godzilla Earth into the discard pile before the
#      play-back — it's destroyed at the check timing after the effect.
func test_esd05_005_godzilla_earth_link_resolves_after_play_back() -> void:
	var earth := Real.instance("EBP04-067")  # rank 7
	var token := Real.instance("EBP04-T01")  # rank 7
	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"), 2: token, 7: earth,
	}, [Cards.battle(6, 5000, "DISCARD-R6")], {"select_zones": [[0, 1, 2]], "select_zone": [3]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	var p0 := state.players[0]
	# Godzilla Earth was not in the discard pile yet, so the R6 was played…
	var search: Dictionary = _calls(s["input"], "search_cards")[0]
	assert_int(search["matching"].size()).is_equal(1)
	assert_str(str(p0.get_zone_top_card(3).get("id"))).is_equal("DISCARD-R6")
	# …then the link destroyed Godzilla Earth.
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_str(str(p0.discard_pile.back().get("id"))).is_equal(str(earth["id"]))


# 11. Tie for highest in discard: player chooses which.
func test_esd05_005_tied_highest_in_discard_lets_player_choose() -> void:
	var second := Cards.battle(7, 6000, "DISCARD-R7B")
	var s := _cf_session({0: Cards.battle(1, 2000, "A"), 1: Cards.battle(1, 2000, "B"), 2: Cards.battle(1, 2000, "C")},
		[Cards.battle(7, 6000, "DISCARD-R7A"), second], {"search_cards": [second], "select_zone": [5]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_int(_calls(s["input"], "search_cards")[0]["matching"].size()).is_equal(2)
	assert_str(str(state.players[0].get_zone_top_card(5).get("id"))).is_equal("DISCARD-R7B")


# 13. An out-of-order answer (e.g. a tampered client) is rejected by the rule
#     and the engine falls back to the forced lowest-first pick.
func test_esd05_005_out_of_order_answer_is_rejected() -> void:
	var c := ZoneSelectConstraints.lowest_first({0: 1, 1: 2, 2: 3, 3: 9})
	assert_bool(ZoneSelectConstraints.is_valid(c, [0, 1, 3])).is_false()
	assert_bool(ZoneSelectConstraints.is_valid(c, [0, 1, 2])).is_true()
	assert_dict(ZoneSelectConstraints.from_json(ZoneSelectConstraints.to_json(c))).is_equal(c)

	var s := _cf_session({
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"),
		2: Cards.battle(3, 2000, "R3"), 3: Cards.battle(9, 9000, "R9"),
	}, [], {"select_zones": [[0, 1, 3]], "select_zone": [6]})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, Real.instance("ESD05-005"))

	assert_bool(state.players[0].zone_has_cards(3)).is_true()
	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal("R9")


# 14. Bot / default greedy input honors lowest-first; bot cast gate.
func test_esd05_005_default_input_picks_lowest_first() -> void:
	var c := ZoneSelectConstraints.lowest_first({0: 5, 1: 1, 2: 3, 3: 2})
	var picks: Array[int] = PlayerInput.new().select_zones(0, 0, [0, 1, 2, 3] as Array[int], 3, false, "p", c)
	assert_array(picks).contains_exactly_in_any_order([1, 3, 2])


func test_esd05_005_bot_casts_only_when_three_die_and_play_back_is_better() -> void:
	var effect: CardEffect = load("res://scripts/effects/esd05/esd05_005.gd").new()
	var opp := PlayerState.new()
	var base_zones := {0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"), 2: Cards.battle(3, 2000, "R3")}

	var good := States.make_state({"p0": {"zone_cards": base_zones}}).players[0]
	good.discard_pile.append(Cards.battle(7, 6000, "D-R7"))
	assert_bool(effect.bot_can_fulfill_on_enter(good, opp)).is_true()

	var no_upgrade := States.make_state({"p0": {"zone_cards": base_zones}}).players[0]
	no_upgrade.discard_pile.append(Cards.battle(2, 2000, "D-R2"))
	assert_bool(effect.bot_can_fulfill_on_enter(no_upgrade, opp)) \
		.override_failure_message("play-back must beat the best card given up").is_false()

	var too_few := States.make_state({"p0": {"zone_cards": {0: Cards.battle(1, 2000, "R1")}}}).players[0]
	too_few.discard_pile.append(Cards.battle(7, 6000, "D-R7"))
	assert_bool(effect.bot_can_fulfill_on_enter(too_few, opp)).is_false()

	var replacer := States.make_state({"p0": {"zone_cards": {
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"), 2: Real.instance("ESD01-011"),
	}}}).players[0]
	replacer.discard_pile.append(Cards.battle(7, 6000, "D-R7"))
	assert_bool(effect.bot_can_fulfill_on_enter(replacer, opp)) \
		.override_failure_message("replace-on-destroy in the forced 3 stalls the effect").is_false()

	# Opponent-only protection (EBP03-053) doesn't stop our own effect.
	var opp_only := States.make_state({"p0": {"zone_cards": {
		0: Cards.battle(1, 2000, "R1"), 1: Cards.battle(2, 2000, "R2"), 2: Real.instance("EBP03-053"),
	}}}).players[0]
	opp_only.discard_pile.append(Cards.battle(9, 9000, "D-R9"))
	assert_bool(effect.bot_can_fulfill_on_enter(opp_only, opp)).is_true()


# --- ESD03-004: Godzilla(2026) rank IV — enter: reveal zone-number cards,
# --- add 1 red Godzilla monster, shuffle the rest back ---


func test_esd03_004_reveals_zone_number_and_adds_red_godzilla_monster() -> void:
	var card := Real.instance("ESD03-004")
	var blue_godzilla := Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "BLUE-GOD")
	blue_godzilla["colors"] = [CardEnums.CardColor.BLUE]
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 4, "main_deck": [
			Cards.battle(2, 3000, "D-BTL"),
			Cards.monster(3, 9000, [CardEnums.CardTrait.MOTHRA], "RED-MOTHRA"),
			blue_godzilla,
			Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "RED-GOD"),
			Cards.battle(1, 2000, "D-UNREVEALED"),
		]},
	})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	# Zone 4 → 4 cards revealed; only the red Godzilla monster is selectable.
	var pick: Dictionary = input.calls.filter(
		func(c: Dictionary) -> bool: return c["kind"] == "search_cards")[0]
	assert_int(pick["matching"].size()).is_equal(1)
	assert_str(str(pick["matching"][0]["id"])).is_equal("RED-GOD")
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(str(state.players[0].hand[0]["id"])).is_equal("RED-GOD")
	assert_int(state.players[0].main_deck.size()).is_equal(4)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_esd03_004_no_valid_card_returns_all_to_deck() -> void:
	var card := Real.instance("ESD03-004")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2, "main_deck": [
			Cards.battle(2, 3000, "D-1"), Cards.battle(2, 3000, "D-2"), Cards.battle(2, 3000, "D-3"),
		]},
	})
	var s := _session(state)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].main_deck.size()).is_equal(3)


# --- ESD04-005: Godzilla(1995) — opp counter start, no strategy in play:
# --- destroy all own battle cards (itself included) ---


func test_esd04_005_without_strategy_destroys_all_own_battle_cards(has_strategy: bool, swept: bool,
		_test_parameters := [
			[false, true],
			[true, false],
		]) -> void:
	var card := Real.instance("ESD04-005")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {2: card, 5: Cards.battle(3, 2000, "OWN-OTHER")}},
		"p1": {"zone_cards": {4: Cards.battle(3, 2000, "OPP")}},
	})
	if has_strategy:
		state.players[0].strategy_zones[0] = Cards.strategy(1, "OWN-STR")
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].get_battle_card_zone_indices().size()).is_equal(0 if swept else 2)
	assert_bool(state.players[1].zone_has_cards(4)) \
		.override_failure_message("ESD04-005 never touches the opponent's board").is_true()


func test_esd04_005_does_not_fire_on_own_counter_phase() -> void:
	var card := Real.instance("ESD04-005")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := _session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[0].zone_has_cards(2)).is_true()


## Snapshots which zones are highlighted each time a zone is asked for.
class _HighlightAwareInput extends ScriptedPlayerInput:
	var lit: Dictionary = {}
	var lit_at_prompt: Array = []

	func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
		lit_at_prompt.append(lit.keys())
		return super(player_id, target_player_id, valid_zones, prompt, allow_skip)
