extends GdUnitTestSuite

## EffectHandler zone primitives that card scripts call instead of mutating
## zones by hand (scripts/effects/README.md § Per-card scripts).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


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
