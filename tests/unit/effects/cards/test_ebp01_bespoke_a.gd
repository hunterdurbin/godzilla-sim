extends GdUnitTestSuite

## Tier C bespoke tests for EBP01 cards 004-044 (see classification.md).
## One-of-a-kind effects driven through the real trigger-dispatch seam.
## The 045-080 half lives in test_ebp01_bespoke_b.gd.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _session(state: GameState) -> Dictionary:
	var session := States.make_session(state)
	session["state"] = state
	return session


# --- EBP01-004: Godzilla(1954) — reach zone 8 → destroy ALL battle cards ---


func test_ebp01_004_reaching_zone_8_destroys_all_battle_cards() -> void:
	var monster := Real.instance("EBP01-004")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 8,
			"zone_cards": {1: Cards.battle(3, 2000, "MINE-A"), 4: Cards.battle(8, 9000, "MINE-B")}},
		"p1": {"zone_cards": {2: Cards.battle(2, 2000, "OPP-A"), 6: Cards.battle(7, 8000, "OPP-B")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_monster_advance(0, 7, 8)

	assert_int(state.players[0].get_battle_card_zone_indices().size()).is_equal(0)
	assert_int(state.players[1].get_battle_card_zone_indices().size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(2)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(handler.queries.get_burst_rank(monster)).is_equal(3)


func test_ebp01_004_silent_below_zone_8() -> void:
	var monster := Real.instance("EBP01-004")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 7, "zone_cards": {1: Cards.battle(3, 2000, "MINE")}},
		"p1": {"zone_cards": {2: Cards.battle(2, 2000, "OPP")}},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_monster_advance(0, 6, 7)

	assert_bool(state.players[0].zone_has_cards(1)).is_true()
	assert_bool(state.players[1].zone_has_cards(2)).is_true()


# --- EBP01-005: Godzilla(1955) — Burst3; enter: opponent discards to 4 ---


func test_ebp01_005_enter_discards_opponent_down_to_4() -> void:
	var monster := Real.instance("EBP01-005")
	var hand: Array = []
	for i in range(6):
		hand.append(Cards.battle(1, 2000, "H%d" % i))
	var state := States.make_state({"p0": {"current_monster": monster}, "p1": {"hand": hand}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[5, 4]]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[1].hand.size()).is_equal(4)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(handler.queries.get_burst_rank(monster)).is_equal(3)

	# Already at 4 or fewer: no discard prompt at all.
	var monster2 := Real.instance("EBP01-005", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2}, "p1": {"hand": [Cards.battle(1, 2000, "K")]}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, monster2)
	assert_int(state2.players[1].hand.size()).is_equal(1)
	assert_int(input2.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP01-008: Godzilla(2004) — Burst2; enter: advance opponent monster 1 ---


func test_ebp01_008_enter_advances_opponent_monster_one_zone() -> void:
	var monster := Real.instance("EBP01-008")
	var state := States.make_state({"p0": {"current_monster": monster}, "p1": {"monster_zone": 4}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, monster)
	assert_int(state.players[1].monster_zone).is_equal(5)
	assert_int(handler.queries.get_burst_rank(monster)).is_equal(2)

	# Opponent already at zone 8: stays put.
	var monster2 := Real.instance("EBP01-008", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2}, "p1": {"monster_zone": 8}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, monster2)
	assert_int(state2.players[1].monster_zone).is_equal(8)


# --- EBP01-011: Fest Godzilla R1 — advance into opp monster column → push it ---


func test_ebp01_011_advancing_into_opponent_monster_column_pushes_it() -> void:
	var monster := Real.instance("EBP01-011")
	# Own zone 5 (idx 4) faces opponent zone 1 — opponent monster there gets pushed.
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 5}, "p1": {"monster_zone": 1}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_monster_advance(0, 4, 5)

	assert_int(state.players[1].monster_zone).is_equal(2)


func test_ebp01_011_silent_outside_column_and_when_opponent_at_8() -> void:
	# Zone 4 faces opponent zone 2 only — opponent at zone 1 is untouched.
	var monster := Real.instance("EBP01-011")
	var state := States.make_state({"p0": {"current_monster": monster, "monster_zone": 4}, "p1": {"monster_zone": 1}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_monster_advance(0, 3, 4)
	assert_int(state.players[1].monster_zone).is_equal(1)

	# In column (zone 3 faces zones 3/8) but opponent already at 8: stays.
	var monster2 := Real.instance("EBP01-011", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2, "monster_zone": 3}, "p1": {"monster_zone": 8}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_monster_advance(0, 2, 3)
	assert_int(state2.players[1].monster_zone).is_equal(8)


# --- EBP01-012: Fest Godzilla R2 — own end phase after invading → push opp ---


func test_ebp01_012_end_phase_after_invading_advances_opponent() -> void:
	var monster := Real.instance("EBP01-012")
	var state := States.make_state({
		"p0": {"current_monster": monster, "has_invaded_this_turn": true},
		"p1": {"monster_zone": 3},
	})
	state.current_phase = CardEnums.GamePhase.END
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(state.players[1].monster_zone).is_equal(4)


func test_ebp01_012_silent_without_invasion_wrong_turn_or_phase() -> void:
	# Did not invade: no advance.
	var monster := Real.instance("EBP01-012")
	var state := States.make_state({"p0": {"current_monster": monster}, "p1": {"monster_zone": 3}})
	state.current_phase = CardEnums.GamePhase.END
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# Invaded, but it's the opponent's end phase.
	state.players[0].has_invaded_this_turn = true
	state.current_player_id = 1
	await handler.trigger_phase_start(CardEnums.GamePhase.END)
	assert_int(state.players[1].monster_zone).is_equal(3)

	# Own MAIN phase: the phase filter gates it off.
	state.current_player_id = 0
	state.current_phase = CardEnums.GamePhase.MAIN
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(state.players[1].monster_zone).is_equal(3)


# --- EBP01-013: Fest Godzilla R3 — enter w/ 4+ battle cards → opp rage -1 ---


func test_ebp01_013_enter_reduces_opponent_rage_with_4_battle_cards() -> void:
	var monster := Real.instance("EBP01-013")
	var state := States.make_state({
		"p0": {"current_monster": monster, "zone_cards": {
			1: Cards.battle(1, 2000, "B1"), 2: Cards.battle(1, 2000, "B2"),
			3: Cards.battle(1, 2000, "B3"), 4: Cards.battle(1, 2000, "B4"),
		}},
		"p1": {"rage": 2},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, monster)
	assert_int(state.players[1].rage).is_equal(1)
	assert_int(handler.queries.get_burst_rank(monster)).is_equal(2)

	# Only 3 battle cards: silent.
	var monster2 := Real.instance("EBP01-013", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": monster2, "zone_cards": {
			1: Cards.battle(1, 2000, "C1"), 2: Cards.battle(1, 2000, "C2"), 3: Cards.battle(1, 2000, "C3"),
		}},
		"p1": {"rage": 2},
	})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, monster2)
	assert_int(state2.players[1].rage).is_equal(2)


# --- EBP01-015: Fest Godzilla R4 — your-turn enter: mill 5, rage per monster,
# --- advance to zone 6 on a Step2 reveal ---


func test_ebp01_015_enter_mills_5_gaining_rage_and_advancing_on_step2() -> void:
	var monster := Real.instance("EBP01-015")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"main_deck": [
			Cards.monster(1, 5000, [], "M1"),
			Cards.battle(2, 2000, "STEP2", [], 2),
			Cards.battle(1, 2000, "B1"),
			Cards.monster(2, 9000, [], "M2"),
			Cards.strategy(2, "S1"),
			Cards.battle(1, 2000, "BELOW"),
		],
	}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	var p0 := state.players[0]
	assert_int(p0.rage).is_equal(2)
	assert_int(p0.monster_zone).is_equal(6)
	assert_int(p0.discard_pile.size()).is_equal(5)
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("BELOW")


func test_ebp01_015_silent_on_opponent_turn_and_without_monsters_or_step2() -> void:
	var monster := Real.instance("EBP01-015")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster, "main_deck": [Cards.battle(1, 2000, "D1")]},
	})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, monster)
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(state.players[0].rage).is_equal(0)

	# Own turn, but no monsters and no Step2 revealed: mill only.
	var monster2 := Real.instance("EBP01-015", 1)
	var deck2: Array = []
	for i in range(5):
		deck2.append(Cards.battle(1, 2000, "P%d" % i))
	var state2 := States.make_state({"p0": {"current_monster": monster2, "main_deck": deck2}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, monster2)
	assert_int(state2.players[0].discard_pile.size()).is_equal(5)
	assert_int(state2.players[0].rage).is_equal(0)
	assert_int(state2.players[0].monster_zone).is_equal(1)


# --- EBP01-020: Anguirus(1968) — in zone 8, on own invasion may pay 1 rage
# --- to search a Burst monster ---


func test_ebp01_020_invasion_in_zone_8_may_pay_rage_to_search_burst_monster() -> void:
	var card := Real.instance("EBP01-020")
	var burst := Real.instance("EBP01-004")
	var state := States.make_state({"p0": {
		"zone_cards": {7: card},
		"rage": 1,
		"main_deck": [Cards.monster(2, 9000, [], "PLAIN-MON"), burst, Cards.battle(1, 2000, "B1")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0], "search_cards": [{"id": burst.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_invasion_observed(0, 3, 4)

	var p0 := state.players[0]
	assert_int(p0.rage).is_equal(0)
	assert_str(str(p0.hand[0].get("id"))).is_equal(str(burst.get("id")))
	assert_int(p0.main_deck.size()).is_equal(2)
	# Search pool: only monsters with <Burst> (the plain monster has no effect).
	assert_int(input.calls[1]["matching"].size()).is_equal(1)


func test_ebp01_020_silent_when_declined_misplaced_or_without_rage() -> void:
	# Declines the offer: rage kept, no search.
	var card := Real.instance("EBP01-020")
	var state := States.make_state({"p0": {"zone_cards": {7: card}, "rage": 1, "main_deck": [Real.instance("EBP01-004")]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_invasion_observed(0, 3, 4)
	assert_int(state.players[0].rage).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Not in zone 8: never prompts.
	var card2 := Real.instance("EBP01-020", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}, "rage": 1}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_invasion_observed(0, 3, 4)
	assert_int(input2.count_calls("choose_option")).is_equal(0)

	# No rage to pay: never prompts.
	var card3 := Real.instance("EBP01-020", 2)
	var state3 := States.make_state({"p0": {"zone_cards": {7: card3}}})
	var input3 := ScriptedPlayerInput.new()
	var s3 := States.make_session(state3, input3)
	await s3["effect_handler"].trigger_invasion_observed(0, 3, 4)
	assert_int(input3.count_calls("choose_option")).is_equal(0)


# --- EBP01-021: Rodan(1968) — enter in opp monster column: arrange top 2 ---


func test_ebp01_021_enter_in_opponent_monster_column_arranges_top_2() -> void:
	var card := Real.instance("EBP01-021")
	var d1 := Cards.battle(1, 2000, "TOP1")
	var d2 := Cards.battle(1, 2000, "TOP2")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "main_deck": [d1, d2, Cards.battle(1, 2000, "D3")]},
		"p1": {"monster_zone": 3},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"arrange_deck": [{"keep": [d2], "discard": [d1]}]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_enter(0, card)

	var p0 := state.players[0]
	assert_str(str(p0.main_deck[0].get("id"))).is_equal("TOP2")
	assert_int(p0.main_deck.size()).is_equal(2)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("TOP1")
	assert_int(input.calls[0]["cards"].size()).is_equal(2)

	# Opponent monster outside the column: deck untouched, no prompt.
	var card2 := Real.instance("EBP01-021", 1)
	var state2 := States.make_state({
		"p0": {"zone_cards": {2: card2}, "main_deck": [Cards.battle(1, 2000, "X1")]},
		"p1": {"monster_zone": 1},
	})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[0].main_deck.size()).is_equal(1)
	assert_int(input2.count_calls("arrange_deck")).is_equal(0)


# --- EBP01-022: Titanosaurus — your-turn rage increase: may move another
# --- battle card to an empty zone ---


func test_ebp01_022_own_rage_increase_moves_another_battle_card_to_empty_zone() -> void:
	var card := Real.instance("EBP01-022")
	var other := Cards.battle(2, 2000, "MOVE-ME")
	var state := States.make_state({"p0": {"zone_cards": {1: card, 3: other}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [3, 5]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.gain_rage(0, 1)

	assert_bool(state.players[0].zone_has_cards(3)).is_false()
	assert_str(str(state.players[0].get_zone_top_card(5).get("id"))).is_equal("MOVE-ME")
	# The source prompt offers only OTHER battle cards (its own zone excluded).
	assert_int(input.calls[0]["valid"].size()).is_equal(1)
	assert_bool(1 in input.calls[0]["valid"]).is_false()


func test_ebp01_022_silent_on_opponent_turn_decrease_or_skip() -> void:
	# Opponent's turn: no prompt even though rage went up.
	var card := Real.instance("EBP01-022")
	var other := Cards.battle(2, 2000, "STAY")
	var state := States.make_state({"current_player_id": 1, "p0": {"zone_cards": {1: card, 3: other}}})
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	await handler.gain_rage(0, 1)
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Own turn but a rage DECREASE: direction filter gates it off.
	state.current_player_id = 0
	await handler.reduce_rage(0, 1)
	assert_int(input.count_calls("select_zone")).is_equal(0)

	# Skipping the move keeps the board.
	input.answers = {"select_zone": [-1]}
	await handler.gain_rage(0, 1)
	assert_bool(state.players[0].zone_has_cards(3)).is_true()
	assert_int(input.count_calls("select_zone")).is_equal(1)


# --- EBP01-024: Minilla(2004) — enter: reduce opponent rage 1 ---


func test_ebp01_024_enter_reduces_opponent_rage_by_1() -> void:
	var card := Real.instance("EBP01-024")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}, "p1": {"rage": 2}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].rage).is_equal(1)

	# Opponent at 0 rage: stays at 0 (no underflow).
	var card2 := Real.instance("EBP01-024", 1)
	var state2 := States.make_state({"p0": {"zone_cards": {2: card2}}})
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].rage).is_equal(0)


# --- EBP01-026: Jet Jaguar(2023) — own counter phase: stack Gigan+Fest from
# --- discard under it; +5000 CP while stacked ---


func test_ebp01_026_counter_phase_stacks_gigan_fest_from_discard_for_5000_cp() -> void:
	var card := Real.instance("EBP01-026")
	var gf := Cards.battle(2, 2000, "GF", [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.FEST])
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append_array([gf, Cards.battle(2, 2000, "ONLY-GIGAN", [CardEnums.CardTrait.GIGAN])])
	state.current_phase = CardEnums.GamePhase.COUNTER
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "GF"}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(2)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(12000)
	# Only the card with BOTH traits was offered.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_ebp01_026_no_bonus_without_card_under_and_gated_to_own_counter_phase() -> void:
	var card := Real.instance("EBP01-026")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	state.players[0].discard_pile.append(Cards.battle(2, 2000, "GF2", [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.FEST]))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# Nothing stacked yet: base CP only.
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(7000)

	# Main phase: filter blocks it.
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	# Opponent's counter phase: still silent.
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.COUNTER
	await handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	assert_int(input.count_calls("search_cards")).is_equal(0)


# --- EBP01-030: Godzilla Landing — advance opponent monster 1 zone ---


func test_ebp01_030_enter_advances_opponent_monster() -> void:
	var card := Real.instance("EBP01-030")
	var state := States.make_state({"p1": {"monster_zone": 4}})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_enter(0, card)
	assert_int(state.players[1].monster_zone).is_equal(5)

	# Opponent already at 8: stays.
	var card2 := Real.instance("EBP01-030", 1)
	var state2 := States.make_state({"p1": {"monster_zone": 8}})
	state2.players[0].strategy_zones[0] = card2
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_enter(0, card2)
	assert_int(state2.players[1].monster_zone).is_equal(8)


# --- EBP01-031: Space Beam — rage>=2: opponent discards to 2 ---


func test_ebp01_031_discards_opponent_to_2_only_with_rage_2() -> void:
	var card := Real.instance("EBP01-031")
	var state := States.make_state({
		"p0": {"rage": 2},
		"p1": {"hand": [Cards.battle(1, 2000, "H0"), Cards.battle(1, 2000, "H1"),
			Cards.battle(1, 2000, "H2"), Cards.battle(1, 2000, "H3")]},
	})
	state.players[0].strategy_zones[0] = card
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[3, 2]]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_enter(0, card)
	assert_int(state.players[1].hand.size()).is_equal(2)
	assert_int(state.players[1].discard_pile.size()).is_equal(2)

	# Rage 1: silent.
	var card2 := Real.instance("EBP01-031", 1)
	var state2 := States.make_state({
		"p0": {"rage": 1},
		"p1": {"hand": [Cards.battle(1, 2000, "K0"), Cards.battle(1, 2000, "K1"), Cards.battle(1, 2000, "K2")]},
	})
	state2.players[0].strategy_zones[0] = card2
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_enter(0, card2)
	assert_int(state2.players[1].hand.size()).is_equal(3)
	assert_int(input2.count_calls("choose_hand_discards")).is_equal(0)


# --- EBP01-033: Final Showdown — self rank -1 per zone invaded; enter:
# --- destroy all battle cards of both players ---


func test_ebp01_033_play_rank_drops_by_zones_invaded_this_turn() -> void:
	var card := Real.instance("EBP01-033")
	var state := States.make_state({"p0": {"hand": [card]}})
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)

	state.players[0].invasion_zones_crossed = 3
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-3)


func test_ebp01_033_enter_destroys_all_battle_cards_on_both_sides() -> void:
	var card := Real.instance("EBP01-033")
	var state := States.make_state({
		"p0": {"zone_cards": {1: Cards.battle(2, 2000, "MINE")}},
		"p1": {"zone_cards": {3: Cards.battle(8, 9000, "OPP")}},
	})
	state.players[0].strategy_zones[0] = card
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, card)

	assert_int(state.players[0].get_battle_card_zone_indices().size()).is_equal(0)
	assert_int(state.players[1].get_battle_card_zone_indices().size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


# --- EBP01-035: Godzilla(1989) — enter: evolve adjacent rank<=4 Evolution ---


func test_ebp01_035_enter_evolves_adjacent_rank_4_evolution_cards_only() -> void:
	var monster := Real.instance("EBP01-035")
	var egg := Real.instance("EBP01-044")        # rank 1 Evolution5 — eligible
	var big_evo := Real.instance("EBP01-054")    # rank 6 Evolution8 — over the cap
	var far_evo := Real.instance("EBP01-050")    # eligible rank but not adjacent
	var target := Real.instance("EBP01-050", 1)
	var state := States.make_state({"p0": {
		"current_monster": monster, "monster_zone": 4,
		"zone_cards": {2: egg, 4: big_evo, 0: far_evo},
		"main_deck": [target, Cards.battle(3, 2000, "DECOY")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	assert_int(p0.get_zone_stack(4).size()).is_equal(1)
	assert_int(p0.get_zone_stack(0).size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(1)
	# Evolution search pool: Mothra battle cards of rank <= 5 only.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)


# --- EBP01-036: Godzilla(1992) — enter: evolve ALL adjacent Evolution cards ---


func test_ebp01_036_enter_evolves_adjacent_evolution_cards_of_any_rank() -> void:
	var monster := Real.instance("EBP01-036")
	var flying := Real.instance("EBP01-054")     # rank 6 — eligible (no rank cap)
	var target := Real.instance("EBP01-049", 1)  # Destoroyah rank 4 <= Evolution8
	var state := States.make_state({"p0": {
		"current_monster": monster, "monster_zone": 4,
		"zone_cards": {2: flying, 4: Cards.battle(5, 4000, "PLAIN")},
		"main_deck": [target],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(2).get("id"))).is_equal(str(target.get("id")))
	assert_int(p0.get_zone_stack(2).size()).is_equal(2)
	# Non-Evolution neighbor untouched.
	assert_int(p0.get_zone_stack(4).size()).is_equal(1)
	assert_int(input.count_calls("search_cards")).is_equal(1)


# --- EBP01-037: Godzilla(1995) — on advance, may discard a strategy for rage ---


func test_ebp01_037_advance_may_discard_strategy_for_rage() -> void:
	var monster := Real.instance("EBP01-037")
	var state := States.make_state({"p0": {
		"current_monster": monster,
		"hand": [Cards.battle(1, 2000, "B"), Cards.strategy(2, "S")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_monster_advance(0, 1, 2)

	assert_int(state.players[0].rage).is_equal(1)
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("S")
	# Only the strategy card was offered as the cost.
	assert_int(input.calls[0]["valid"].size()).is_equal(1)
	assert_bool(0 in input.calls[0]["valid"]).is_false()


func test_ebp01_037_skip_or_no_strategy_in_hand_gains_nothing() -> void:
	var monster := Real.instance("EBP01-037")
	var state := States.make_state({"p0": {"current_monster": monster, "hand": [Cards.strategy(2, "S")]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)
	await s["effect_handler"].trigger_monster_advance(0, 1, 2)
	assert_int(state.players[0].rage).is_equal(0)
	assert_int(state.players[0].hand.size()).is_equal(1)

	# No strategy in hand: no prompt at all.
	var monster2 := Real.instance("EBP01-037", 1)
	var state2 := States.make_state({"p0": {"current_monster": monster2, "hand": [Cards.battle(1, 2000, "B")]}})
	var input2 := ScriptedPlayerInput.new()
	var s2 := States.make_session(state2, input2)
	await s2["effect_handler"].trigger_monster_advance(0, 1, 2)
	assert_int(input2.count_calls("select_hand_card")).is_equal(0)
	assert_int(state2.players[0].rage).is_equal(0)


# --- EBP01-039: Godzilla(1999) — when invading, discard a monster from hand
# --- to destroy all opp rank<=5 battle cards in zones 1-5 ---


func test_ebp01_039_invading_discard_monster_destroys_opp_rank_5_in_zones_1_5() -> void:
	var monster := Real.instance("EBP01-039")
	var state := States.make_state({
		"p0": {"current_monster": monster, "hand": [Cards.monster(2, 9000, [], "COST"), Cards.battle(2, 2000, "B")]},
		"p1": {"zone_cards": {
			1: Cards.battle(5, 4000, "R5-BACK"),
			2: Cards.battle(6, 5000, "R6-BACK"),
			6: Cards.battle(5, 4000, "R5-FRONT"),
		}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_when_invading(0, 2, 3)

	var p1 := state.players[1]
	assert_bool(p1.zone_has_cards(1)).is_false()
	assert_bool(p1.zone_has_cards(2)).is_true()   # rank 6: too big
	assert_bool(p1.zone_has_cards(6)).is_true()   # zone 7: outside zones 1-5
	assert_str(str(state.players[0].discard_pile[0].get("id"))).is_equal("COST")
	# Only the monster in hand was offered as the cost.
	assert_int(input.calls[0]["valid"].size()).is_equal(1)


func test_ebp01_039_skipping_the_cost_destroys_nothing() -> void:
	var monster := Real.instance("EBP01-039")
	var state := States.make_state({
		"p0": {"current_monster": monster, "hand": [Cards.monster(2, 9000, [], "COST")]},
		"p1": {"zone_cards": {1: Cards.battle(2, 2000, "OPP")}},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var s := States.make_session(state, input)

	await s["effect_handler"].trigger_when_invading(0, 2, 3)

	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_int(state.players[0].hand.size()).is_equal(1)


# --- EBP01-042: Godzilla(2000) R3 — 5+ monsters in discard: may discard 1 to
# --- reduce opp rage; +10000 threat level ---


func test_ebp01_042_enter_with_5_discarded_monsters_reduces_rage_and_boosts_threat() -> void:
	var monster := Real.instance("EBP01-042")
	var state := States.make_state({
		"p0": {"current_monster": monster, "rage": 1, "hand": [Cards.battle(2, 2000, "PAY")]},
		"p1": {"rage": 2},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [0]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[1].rage).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(0)
	# 18000 base + 1 rage (5000) + 10000 from the 5-monster discard pile.
	assert_int(handler.get_effective_threat_level(0)).is_equal(33000)


func test_ebp01_042_silent_below_5_monsters_in_discard() -> void:
	var monster := Real.instance("EBP01-042")
	var state := States.make_state({
		"p0": {"current_monster": monster, "hand": [Cards.battle(2, 2000, "PAY")]},
		"p1": {"rage": 2},
	})
	for i in range(4):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var input := ScriptedPlayerInput.new()
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_enter(0, monster)

	assert_int(state.players[1].rage).is_equal(2)
	assert_int(input.count_calls("select_hand_card")).is_equal(0)
	assert_int(handler.get_effective_threat_level(0)).is_equal(18000)


# --- EBP01-043: Godzilla(2000) R4 — Awakening4 counter success w/ 5 monsters
# --- in discard: destroy all opp rank<=6 battle cards ---


func test_ebp01_043_counter_success_awakening4_with_5_monsters_destroys_rank_6() -> void:
	var monster := Real.instance("EBP01-043")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": monster, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(6, 5000, "R6"), 3: Cards.battle(7, 8000, "R7")}},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.trigger_counter_success(0, 1)

	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(3)).is_true()


func test_ebp01_043_silent_without_awakening_or_5_monsters() -> void:
	# Zone 3: no Awakening4.
	var monster := Real.instance("EBP01-043")
	var state := States.make_state({
		"p0": {"current_monster": monster, "monster_zone": 3},
		"p1": {"zone_cards": {1: Cards.battle(6, 5000, "R6")}},
	})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [], "DM%d" % i))
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]
	await handler.trigger_counter_success(0, 1)
	assert_bool(state.players[1].zone_has_cards(1)).is_true()

	# Awakening4, but only 4 monsters in discard.
	var monster2 := Real.instance("EBP01-043", 1)
	var state2 := States.make_state({
		"p0": {"current_monster": monster2, "monster_zone": 4},
		"p1": {"zone_cards": {1: Cards.battle(6, 5000, "R6B")}},
	})
	for i in range(4):
		state2.players[0].discard_pile.append(Cards.monster(1, 5000, [], "EM%d" % i))
	var s2 := _session(state2)
	var handler2: EffectHandler = s2["effect_handler"]
	await handler2.trigger_counter_success(0, 1)
	assert_bool(state2.players[1].zone_has_cards(1)).is_true()


# --- EBP01-044: Mothra(egg)(1992) — main phase: Evolution5 <Mothra> ---


func test_ebp01_044_main_phase_evolves_into_rank_5_mothra() -> void:
	var card := Real.instance("EBP01-044")
	var target := Real.instance("EBP01-050")     # rank 4 Mothra — eligible
	var too_big := Real.instance("EBP01-057")    # rank 7 Mothra — over Evolution5
	var state := States.make_state({"p0": {
		"zone_cards": {1: card},
		"main_deck": [too_big, target, Cards.battle(3, 2000, "NOT-MOTHRA")],
	}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": target.get("id")}]}
	var s := States.make_session(state, input)
	var handler: EffectHandler = s["effect_handler"]

	# Opponent's turn first: the evolution prompt must not appear.
	state.current_player_id = 1
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	assert_int(input.count_calls("search_cards")).is_equal(0)

	state.current_player_id = 0
	await handler.trigger_phase_start(CardEnums.GamePhase.MAIN)

	assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal(str(target.get("id")))
	assert_int(state.players[0].get_zone_stack(1).size()).is_equal(2)
	# Pool excludes rank > 5 and non-Mothra cards.
	assert_int(input.calls[0]["matching"].size()).is_equal(1)
