extends GdUnitTestSuite

## EffectHandler prompt flows driven by ScriptedPlayerInput — the decisions
## resolve synchronously, the state mutation stays in the EffectHandler.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _make_handler(state: GameState, input: PlayerInput) -> EffectHandler:
	var handler := EffectHandler.new()
	handler.setup(state, input)
	return handler


func test_discard_hand_to_uses_scripted_indices() -> void:
	var state := States.make_state({"p0": {"hand": [
		Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C"),
	]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_hand_discards": [[0, 2]]}
	var handler := _make_handler(state, input)

	var discarded: Array[Dictionary] = await handler.discard_hand_to(0, 1)

	assert_int(discarded.size()).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("B")
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


func test_discard_hand_to_default_discards_from_back() -> void:
	var state := States.make_state({"p0": {"hand": [
		Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C"),
	]}})
	var handler := _make_handler(state, PlayerInput.new())

	var discarded: Array[Dictionary] = await handler.discard_hand_to(0, 1)

	assert_int(discarded.size()).is_equal(2)
	assert_str(str(state.players[0].hand[0].get("id"))).is_equal("A")


func test_discard_hand_to_noop_when_at_or_below_target() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}})
	var handler := _make_handler(state, PlayerInput.new())
	assert_array(await handler.discard_hand_to(0, 3)).is_empty()
	assert_int(state.players[0].hand.size()).is_equal(1)


func test_search_deck_removes_selected_and_shuffles() -> void:
	var state := States.make_state({"p0": {"main_deck": [
		Cards.battle(1, 5000, "A"), Cards.strategy(1, "S"), Cards.battle(2, 6000, "B"),
	]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{"id": "B"}]}  # JSON-roundtrip shape: id only
	var handler := _make_handler(state, input)

	var battle_filter := func(card: Dictionary) -> bool:
		return card.get("card_type") == CardEnums.CardType.BATTLE
	var selected: Dictionary = await handler.search_deck(0, battle_filter, "pick a battle card")

	assert_str(str(selected.get("id"))).is_equal("B")
	assert_int(int(selected.get("rank", -1))).is_equal(2)  # canonical deck dict, not the {"id": ...} stub
	assert_int(state.players[0].main_deck.size()).is_equal(2)
	# Offered pool was filter-matched only.
	assert_int(input.calls[0]["matching"].size()).is_equal(2)


func test_search_discard_skip_returns_empty() -> void:
	var state := States.make_state()
	state.players[0].discard_pile.append(Cards.battle(1, 5000, "A"))
	var input := ScriptedPlayerInput.new()
	input.answers = {"search_cards": [{}]}  # player skips
	var handler := _make_handler(state, input)

	var selected: Dictionary = await handler.search_discard(0, func(_c: Dictionary) -> bool: return true, "p")

	assert_bool(selected.is_empty()).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_select_hand_card_discards_chosen_card() -> void:
	var state := States.make_state({"p0": {"hand": [
		Cards.battle(1, 5000, "A"), Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "M"),
	]}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_hand_card": [1]}
	var handler := _make_handler(state, input)

	var monster_filter := func(card: Dictionary) -> bool:
		return card.get("card_type") == CardEnums.CardType.MONSTER
	var card: Dictionary = await handler.select_hand_card(0, monster_filter, "discard a monster")

	assert_str(str(card.get("id"))).is_equal("M")
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	# Only the matching index was offered.
	assert_array(input.calls[0]["valid"]).contains_exactly([1])


func test_select_choice_passes_options_and_clears_card_ids() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var handler := _make_handler(state, input)

	var ids: Array[String] = ["EBP01-001", "EBP01-002"]
	var index: int = await handler.select_choice(0, ["opt a", "opt b"], "choose", ids)

	assert_int(index).is_equal(1)
	assert_array(handler.choice_card_ids).is_empty()


func test_select_zone_target_empty_zones_short_circuits() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	var handler := _make_handler(state, input)
	var empty: Array[int] = []
	assert_int(await handler.select_zone_target(0, 1, empty, "p")).is_equal(-1)
	assert_int(input.calls.size()).is_equal(0)  # input never consulted


func test_select_zones_target_empty_zones_short_circuits() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	var handler := _make_handler(state, input)
	var empty: Array[int] = []
	assert_array(await handler.select_zones_target(0, 1, empty, 3, "p")).is_empty()
	assert_array(await handler.select_zones_target(0, 1, [2] as Array[int], 0, "p")).is_empty()
	assert_int(input.calls.size()).is_equal(0)  # input never consulted


func test_destroy_zone_targets_up_to_decline_destroys_nothing() -> void:
	var state := States.make_state({"p1": {"zone_cards": {
		1: Cards.battle(3, 3000, "A"), 4: Cards.battle(2, 2000, "B"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zones": [[]]}  # Up-to: confirming 0 declines
	var handler := _make_handler(state, input)
	var any_filter := func(_card: Dictionary) -> bool: return true

	var destroyed: Array[Dictionary] = await handler.destroy_zone_targets(
		0, state.players[1], any_filter, 2, "p", true)

	assert_array(destroyed).is_empty()
	assert_bool(state.players[1].zone_has_cards(1)).is_true()
	assert_bool(state.players[1].zone_has_cards(4)).is_true()


func test_destroy_zone_targets_rejects_invalid_and_duplicate_picks() -> void:
	var state := States.make_state({"p1": {"zone_cards": {
		1: Cards.battle(3, 3000, "A"), 4: Cards.battle(2, 2000, "B"),
	}}})
	var input := ScriptedPlayerInput.new()
	# Zone 6 was never offered; the duplicate 1 must count once.
	input.answers = {"select_zones": [[1, 1, 6]]}
	var handler := _make_handler(state, input)
	var any_filter := func(_card: Dictionary) -> bool: return true

	var destroyed: Array[Dictionary] = await handler.destroy_zone_targets(
		0, state.players[1], any_filter, 2, "p")

	assert_int(destroyed.size()).is_equal(1)
	assert_bool(state.players[1].zone_has_cards(1)).is_false()
	assert_bool(state.players[1].zone_has_cards(4)).is_true()


func test_destroy_zones_within_rank_budget_is_one_multi_select_with_budget() -> void:
	# One select/deselect + confirm prompt: every card that fits the budget on
	# its own is offered, each weighted by its rank, up-to mode (confirming
	# nothing declines). The confirmed cards are destroyed together.
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(3, 3000, "R3"), 1: Cards.battle(2, 2000, "R2"),
		2: Cards.battle(4, 4000, "R4"), 3: Cards.battle(6, 6000, "R6"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zones": [[0, 1]]}
	var handler := _make_handler(state, input)

	var destroyed: Array[Dictionary] = await handler.destroy_zones_within_rank_budget(
		0, state.players[1], 5, "budget %d")

	assert_int(input.calls.size()).is_equal(1)
	var prompt_call: Dictionary = input.calls[0]
	assert_str(prompt_call["kind"]).is_equal("select_zones")
	assert_array(prompt_call["valid"]).contains_exactly([0, 1, 2])  # rank 6 never fits
	assert_bool(prompt_call["up_to"]).is_true()
	assert_str(str(prompt_call["prompt"])).is_equal("budget 5")
	assert_dict(prompt_call["constraints"]).is_equal({"weights": {0: 3, 1: 2, 2: 4}, "budget": 5})
	assert_int(destroyed.size()).is_equal(2)
	assert_array(state.players[1].get_battle_card_zone_indices()).contains_exactly([2, 3])


func test_destroy_zones_within_rank_budget_rejects_over_budget_answer() -> void:
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(3, 3000, "R3"), 2: Cards.battle(4, 4000, "R4"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zones": [[0, 2]]}  # 7 > 5
	var handler := _make_handler(state, input)

	var destroyed: Array[Dictionary] = await handler.destroy_zones_within_rank_budget(
		0, state.players[1], 5, "p %d")

	assert_array(destroyed).is_empty()
	assert_array(state.players[1].get_battle_card_zone_indices()).contains_exactly([0, 2])


func test_destroy_zones_within_rank_budget_decline_and_filter() -> void:
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(1, 1000, "KEEP"), 1: Cards.battle(1, 1000, "OUT"),
	}}})
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zones": [[]]}
	var handler := _make_handler(state, input)
	var only_keep := func(card: Dictionary) -> bool: return card.get("id") == "KEEP"

	var destroyed: Array[Dictionary] = await handler.destroy_zones_within_rank_budget(
		0, state.players[1], 7, "p %d", only_keep)

	assert_array(destroyed).is_empty()
	assert_array(input.calls[0]["valid"]).contains_exactly([0])
	assert_bool(state.players[1].zone_has_cards(0)).is_true()


func test_default_select_zones_respects_rank_budget() -> void:
	# Unanswered prompts fall back to PlayerInput's default: first zones that
	# still fit the budget.
	var input := PlayerInput.new()
	var constraints := ZoneSelectConstraints.rank_budget({0: 3, 1: 4, 2: 2}, 5)
	var zones: Array[int] = input.select_zones(0, 1, [0, 1, 2] as Array[int], 3, true, "p", constraints)
	assert_array(zones).contains_exactly([0, 2])


func test_zone_select_constraints_budget_math_and_json_round_trip() -> void:
	var c := ZoneSelectConstraints.rank_budget({1: 2, 4: 3, 6: 4}, 5)
	assert_bool(ZoneSelectConstraints.can_add(c, [1], 4)).is_true()   # 2 + 3 = 5
	assert_bool(ZoneSelectConstraints.can_add(c, [1, 4], 6)).is_false()
	assert_bool(ZoneSelectConstraints.is_valid(c, [4, 6])).is_false()  # 7
	assert_int(ZoneSelectConstraints.total(c, [1, 6])).is_equal(6)
	# JSON turns int keys into strings and ints into floats — from_json undoes it.
	assert_dict(ZoneSelectConstraints.from_json(ZoneSelectConstraints.to_json(c))).is_equal(c)
	# No constraints: everything allowed, empty JSON.
	assert_bool(ZoneSelectConstraints.can_add({}, [0, 1, 2], 3)).is_true()
	assert_str(ZoneSelectConstraints.to_json({})).is_empty()
	assert_dict(ZoneSelectConstraints.from_json("")).is_empty()
