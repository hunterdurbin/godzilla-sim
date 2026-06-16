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
