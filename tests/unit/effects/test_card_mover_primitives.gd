extends GdUnitTestSuite

## EffectHandler zone primitives that card scripts call instead of mutating
## zones by hand (scripts/effects/README.md § Per-card scripts).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


## Counts <Enter> resolutions and whether each came from an effect play.
class EnterProbe:
	extends CardEffect
	var entered: Array[bool] = []

	func on_enter(ctx: EffectContext) -> void:
		entered.append(bool(ctx.card_data.get("played_from_effect", false)))


func _ids(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c in cards:
		out.append(str(c.get("id", "")))
	return out


# --- move_zone_card_under_zone ---


func test_move_zone_card_under_zone_tucks_top_card_under_target_top() -> void:
	var mover := Cards.battle(2, 2000, "MOVER")
	var under_mover := Cards.battle(1, 1000, "UNDER-MOVER")
	var target_top := Cards.battle(5, 5000, "TARGET")
	var target_under := Cards.battle(1, 1000, "TARGET-UNDER")
	var state := States.make_state({"p0": {"zone_cards": {7: under_mover, 2: target_under}}})
	var p0 := state.players[0]
	p0.push_zone_card(7, mover)
	p0.push_zone_card(2, target_top)
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	var moved: bool = handler.move_zone_card_under_zone(p0, 7, 2)

	assert_bool(moved).is_true()
	assert_bool(p0.zone_has_cards(7)).is_false()
	# Target keeps its top; the moved card goes to the bottom of the stack.
	assert_array(_ids(p0.get_zone_stack(2))).is_equal(["TARGET", "TARGET-UNDER", "MOVER"])
	# Cards that were under the moved card go to the discard (not destroyed, 5.12.1.1).
	assert_array(_ids(p0.discard_pile)).is_equal(["UNDER-MOVER"])
	assert_array(p0.cards_destroyed_this_turn).is_empty()


func test_move_zone_card_under_zone_noop_for_empty_or_same_zone() -> void:
	var a := Cards.battle(2, 2000, "A")
	var state := States.make_state({"p0": {"zone_cards": {3: a}}})
	var p0 := state.players[0]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	assert_bool(handler.move_zone_card_under_zone(p0, 3, 3)).is_false()
	assert_bool(handler.move_zone_card_under_zone(p0, 5, 3)).is_false()   # empty source
	assert_bool(handler.move_zone_card_under_zone(p0, 3, 6)).is_false()   # empty target
	assert_array(_ids(p0.get_zone_stack(3))).is_equal(["A"])


# --- deck-top primitives ---


func _deck(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		out.append(Cards.battle(1, 1000, id))
	return out


func test_arrange_deck_top_puts_kept_back_in_order_and_discards_rest() -> void:
	var state := States.make_state({"p0": {"main_deck": _deck(["A", "B", "C", "D"])}})
	var p0 := state.players[0]
	var input := ScriptedPlayerInput.new()
	# Keep C then A (C on top); discard B. D was never looked at.
	input.answers = {"arrange_deck": [{"keep": [p0.main_deck[2], p0.main_deck[0]], "discard": [p0.main_deck[1]]}]}
	var handler: EffectHandler = States.make_session(state, input)["effect_handler"]
	var signals: Array[String] = []
	p0.deck_changed.connect(func() -> void: signals.append("deck"))
	p0.discard_changed.connect(func() -> void: signals.append("discard"))

	var result: Dictionary = await handler.arrange_deck_top(0, 3, "arrange")

	assert_array(_ids(p0.main_deck)).is_equal(["C", "A", "D"])
	assert_array(_ids(p0.discard_pile)).is_equal(["B"])
	assert_array(_ids(result["keep"])).is_equal(["C", "A"])
	# Only the 3 looked-at cards were offered.
	assert_int(input.calls_of("arrange_deck").size()).is_equal(1)
	assert_array(_ids(input.calls_of("arrange_deck")[0]["cards"])).is_equal(["A", "B", "C"])
	assert_bool(signals.has("deck")).is_true()
	assert_bool(signals.has("discard")).is_true()


func test_arrange_deck_top_short_and_empty_deck() -> void:
	var state := States.make_state({"p0": {"main_deck": _deck(["ONLY"])}})
	var p0 := state.players[0]
	var input := ScriptedPlayerInput.new()
	var handler: EffectHandler = States.make_session(state, input)["effect_handler"]

	await handler.arrange_deck_top(0, 4, "arrange")  # default input keeps everything
	await handler.check_timing.resolve()
	assert_array(_ids(p0.main_deck)).is_equal(["ONLY"])
	assert_array(_ids(input.calls_of("arrange_deck")[0]["cards"])).is_equal(["ONLY"])

	p0.main_deck.clear()
	var result: Dictionary = await handler.arrange_deck_top(0, 4, "arrange")
	assert_array(result["keep"]).is_empty()
	assert_int(input.calls_of("arrange_deck").size()).is_equal(1)  # no prompt on an empty deck


func test_take_deck_top_takes_from_top_without_prompting() -> void:
	var state := States.make_state({"p0": {"main_deck": _deck(["A", "B", "C"])}})
	var p0 := state.players[0]
	var input := ScriptedPlayerInput.new()
	var handler: EffectHandler = States.make_session(state, input)["effect_handler"]
	var fired: Array[int] = [0]
	p0.deck_changed.connect(func() -> void: fired[0] += 1)

	assert_array(_ids(handler.take_deck_top(0, 2))).is_equal(["A", "B"])
	assert_array(_ids(p0.main_deck)).is_equal(["C"])
	assert_array(_ids(handler.take_deck_top(0, 5))).is_equal(["C"])
	assert_array(handler.take_deck_top(0, 1)).is_empty()
	assert_int(fired[0]).is_equal(2)  # no signal when nothing was taken
	assert_array(input.calls).is_empty()


func test_shuffle_cards_into_deck_is_deterministic_under_a_seed() -> void:
	var runs: Array = []
	for _run in range(2):
		var state := States.make_state({"p0": {"main_deck": _deck(["A", "B", "C", "D", "E"])}})
		var p0 := state.players[0]
		var handler: EffectHandler = States.make_session(state)["effect_handler"]
		var fired: Array[int] = [0]
		p0.deck_changed.connect(func() -> void: fired[0] += 1)
		seed(1234)
		handler.shuffle_cards_into_deck(0, _deck(["X", "Y"]))
		assert_int(p0.main_deck.size()).is_equal(7)
		assert_int(fired[0]).is_equal(1)
		runs.append(_ids(p0.main_deck))
	assert_array(runs[0]).is_equal(runs[1])
	assert_array(runs[0]).contains(["X", "Y"])


# --- strategy-zone primitives ---


func test_play_strategy_from_effect_plays_into_first_empty_zone() -> void:
	var probe := EnterProbe.new()
	var strat := Cards.strategy(9, "FROM-DISCARD")  # rank irrelevant for effect plays
	strat["effect_script"] = "test://enter_probe"
	var state := States.make_state({"turn_number": 5, "p0": {"strategy_zones": [Cards.strategy(1, "OCCUPIED")]}})
	var p0 := state.players[0]
	p0.discard_pile.append(strat)
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]
	handler.registry.register_for_test("test://enter_probe", probe, ["on_enter"])
	var played: Array = []
	(s["events"] as GameEvents).strategy_card_played.connect(
		func(pid: int, card: Dictionary, idx: int) -> void: played.append([pid, card.get("id"), idx]))

	var idx: int = handler.play_strategy_from_effect(0, strat)
	# The <Enter> enters standby; it resolves at the next check timing.
	assert_array(probe.entered).is_empty()
	await handler.check_timing.resolve()

	assert_int(idx).is_equal(1)
	assert_str(str(p0.strategy_zones[1].get("id"))).is_equal("FROM-DISCARD")
	assert_int(p0.strategy_zone_turn_placed[1]).is_equal(5)
	assert_array(p0.discard_pile).is_empty()
	assert_array(played).is_equal([[0, "FROM-DISCARD", 1]])
	assert_array(probe.entered).is_equal([true])


func test_play_strategy_from_effect_noop_without_an_empty_zone() -> void:
	var strat := Cards.strategy(1, "NO-ROOM")
	var state := States.make_state({"p0": {"strategy_zones": [Cards.strategy(1, "A"), Cards.strategy(1, "B")]}})
	var p0 := state.players[0]
	p0.discard_pile.append(strat)
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	assert_int(handler.play_strategy_from_effect(0, strat)).is_equal(-1)
	assert_array(_ids(p0.discard_pile)).is_equal(["NO-ROOM"])


func test_move_strategy_card_under_zone_moves_without_discarding() -> void:
	var strat := Cards.strategy(1, "STRAT")
	var top := Cards.battle(7, 7000, "TOP")
	var state := States.make_state({"p0": {"strategy_zones": [strat], "zone_cards": {3: top}}})
	var p0 := state.players[0]
	p0.strategy_zone_stacks[0] = [Cards.battle(1, 1000, "MARKER")]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	assert_bool(handler.move_strategy_card_under_zone(p0, 0, 3)).is_true()

	assert_bool(p0.strategy_zones[0].is_empty()).is_true()
	assert_array(p0.strategy_zone_stacks[0]).is_empty()
	assert_array(_ids(p0.get_zone_stack(3))).is_equal(["TOP", "STRAT"])
	assert_array(p0.discard_pile).is_empty()


func test_move_strategy_card_under_zone_noop_for_empty_source_or_target() -> void:
	var strat := Cards.strategy(1, "STRAT")
	var state := States.make_state({"p0": {"strategy_zones": [strat], "zone_cards": {3: Cards.battle(2)}}})
	var p0 := state.players[0]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	assert_bool(handler.move_strategy_card_under_zone(p0, 0, 5)).is_false()  # empty target: card stays
	assert_str(str(p0.strategy_zones[0].get("id"))).is_equal("STRAT")
	assert_bool(handler.move_strategy_card_under_zone(p0, 1, 3)).is_false()  # empty strategy zone
	assert_bool(handler.move_strategy_card_under_zone(p0, 0, -1)).is_false()


func test_ensure_strategy_zone_count_grows_parallel_arrays_once() -> void:
	var state := States.make_state()
	var p0 := state.players[0]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]
	var fired: Array[int] = [0]
	p0.strategy_zones_changed.connect(func() -> void: fired[0] += 1)

	assert_bool(handler.ensure_strategy_zone_count(p0, 3)).is_true()
	assert_int(p0.strategy_zones.size()).is_equal(3)
	assert_int(p0.strategy_zone_stacks.size()).is_equal(3)
	assert_int(p0.strategy_zone_turn_placed.size()).is_equal(3)
	assert_bool(p0.strategy_zones[2].is_empty()).is_true()
	assert_bool(handler.ensure_strategy_zone_count(p0, 3)).is_false()
	assert_bool(handler.ensure_strategy_zone_count(p0, 2)).is_false()  # never shrinks
	assert_int(fired[0]).is_equal(1)


# --- place_cards_under_monster ---


func test_place_cards_under_monster_takes_cards_out_of_discard_and_monster_deck() -> void:
	var from_discard := Cards.battle(2, 2000, "FROM-DISCARD")
	var stays := Cards.battle(2, 2000, "STAYS")
	var from_mdeck := Cards.monster(3, 3000, [CardEnums.CardTrait.GODZILLA], "FROM-MDECK")
	var state := States.make_state()
	var p0 := state.players[0]
	p0.discard_pile.append(stays)
	p0.discard_pile.append(from_discard)
	p0.monster_deck.append(from_mdeck)
	var handler: EffectHandler = States.make_session(state)["effect_handler"]
	var signals: Array[String] = []
	p0.discard_changed.connect(func() -> void: signals.append("discard"))
	p0.monster_changed.connect(func() -> void: signals.append("monster"))

	handler.place_cards_under_monster(0, [from_discard, from_mdeck])

	assert_array(_ids(p0.monster_stack)).is_equal(["FROM-DISCARD", "FROM-MDECK"])
	assert_array(_ids(p0.discard_pile)).is_equal(["STAYS"])
	assert_bool(p0.monster_deck.has(from_mdeck)).is_false()
	assert_array(signals).is_equal(["discard", "monster"])


func test_place_cards_under_monster_noop_when_empty() -> void:
	var state := States.make_state()
	var p0 := state.players[0]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]
	var fired: Array[int] = [0]
	p0.monster_changed.connect(func() -> void: fired[0] += 1)

	handler.place_cards_under_monster(0, [])

	assert_array(p0.monster_stack).is_empty()
	assert_int(fired[0]).is_equal(0)


# --- return_cards_under_top_to_hand ---


func test_return_cards_under_top_to_hand_keeps_top_and_adds_rest_to_hand() -> void:
	var under_a := Cards.battle(1, 1000, "UNDER-A")
	var under_b := Cards.battle(1, 1000, "UNDER-B")
	var top := Cards.battle(7, 7000, "TOP")
	var state := States.make_state({"p0": {"zone_cards": {4: under_b}}})
	var p0 := state.players[0]
	p0.push_zone_card(4, under_a)
	p0.push_zone_card(4, top)
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	var returned: Array[Dictionary] = handler.return_cards_under_top_to_hand(p0, 4)

	assert_array(_ids(returned)).is_equal(["UNDER-A", "UNDER-B"])
	assert_array(_ids(p0.get_zone_stack(4))).is_equal(["TOP"])
	assert_array(_ids(p0.hand)).is_equal(["UNDER-A", "UNDER-B"])


func test_return_cards_under_top_to_hand_noop_without_under_cards() -> void:
	var top := Cards.battle(7, 7000, "TOP")
	var state := States.make_state({"p0": {"zone_cards": {4: top}}})
	var p0 := state.players[0]
	var handler: EffectHandler = States.make_session(state)["effect_handler"]

	assert_array(handler.return_cards_under_top_to_hand(p0, 4)).is_empty()
	assert_array(handler.return_cards_under_top_to_hand(p0, 6)).is_empty()
	assert_array(_ids(p0.get_zone_stack(4))).is_equal(["TOP"])
	assert_array(p0.hand).is_empty()


# --- choose_hand_card ---


func test_choose_hand_card_returns_pick_without_moving_it() -> void:
	var a := Cards.battle(1, 1000, "A")
	var b := Cards.battle(2, 2000, "B")
	var state := States.make_state({"p0": {"hand": [a, b]}})
	var p0 := state.players[0]
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var handler: EffectHandler = States.make_session(state, input)["effect_handler"]

	var picked: Dictionary = await handler.choose_hand_card(
		0, func(c: Dictionary) -> bool: return c.get("id") != "A", "pick", true)

	assert_str(str(picked.get("id"))).is_equal("B")
	assert_array(_ids(p0.hand)).is_equal(["A", "B"])
	assert_array(p0.discard_pile).is_empty()
	var calls := input.calls_of("select_hand_card")
	assert_int(calls.size()).is_equal(1)
	if calls.size() == 1:
		assert_array(calls[0]["valid"]).is_equal([1])


func test_choose_hand_card_empty_on_skip_or_no_match() -> void:
	var a := Cards.battle(1, 1000, "A")
	var state := States.make_state({"p0": {"hand": [a]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [-1]}
	var handler: EffectHandler = States.make_session(state, input)["effect_handler"]

	assert_dict(await handler.choose_hand_card(0, func(_c: Dictionary) -> bool: return true, "p", true)).is_empty()
	assert_dict(await handler.choose_hand_card(0, func(_c: Dictionary) -> bool: return false, "p", true)).is_empty()
	assert_int(input.count_calls("select_hand_card")).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
