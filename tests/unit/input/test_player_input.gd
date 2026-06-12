extends GdUnitTestSuite

## Tests for the PlayerInput decision port: base defaults, scripted answers,
## and the SignalPlayerInput request/resolve round trip (including
## synchronous-resolve-during-emit, the old deadlock case).

const Cards := preload("res://tests/fixtures/cards.gd")


# --- Base defaults (headless fallbacks) ---

func test_base_defaults_auto_pick_first() -> void:
	var input := PlayerInput.new()
	assert_int(await input.choose_option(0, ["a", "b"], "p")).is_equal(0)
	assert_int(await input.choose_option(0, [], "p")).is_equal(-1)
	var matching: Array[Dictionary] = [Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B")]
	assert_str(str((await input.search_cards(0, matching, matching, "p", true)).get("id"))).is_equal("A")
	assert_bool((await input.search_cards(0, [], [], "p", true)).is_empty()).is_true()
	assert_int(await input.select_zone(0, 1, [3, 5], "p", false)).is_equal(3)
	assert_int(await input.select_zone(0, 1, [], "p", false)).is_equal(-1)
	assert_int(await input.select_hand_card(0, [2, 4], "p", false)).is_equal(2)
	assert_int(await input.choose_rankup(0, [], [1, 2], "p")).is_equal(1)


func test_base_hand_discard_defaults_to_back_of_hand() -> void:
	var input := PlayerInput.new()
	assert_array(await input.choose_hand_discards(0, 2, 5)).contains_exactly([4, 3])
	# Count capped by hand size.
	assert_array(await input.choose_hand_discards(0, 9, 2)).contains_exactly([1, 0])


func test_base_arrange_deck_keeps_original_order() -> void:
	var input := PlayerInput.new()
	var cards: Array[Dictionary] = [Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B")]
	var result: Dictionary = await input.arrange_deck(0, cards, "p")
	assert_array(result["keep"]).is_equal(cards)
	assert_array(result["discard"]).is_empty()


# --- ScriptedPlayerInput ---

func test_scripted_answers_pop_in_order_then_fall_back() -> void:
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [2, 1]}
	assert_int(await input.choose_option(0, ["a", "b", "c"], "p")).is_equal(2)
	assert_int(await input.choose_option(0, ["a", "b", "c"], "p")).is_equal(1)
	# Queue empty -> base default (first option).
	assert_int(await input.choose_option(0, ["a", "b", "c"], "p")).is_equal(0)
	assert_int(input.count_calls("choose_option")).is_equal(3)


func test_scripted_records_call_details() -> void:
	var input := ScriptedPlayerInput.new()
	input.answers = {"select_zone": [5]}
	var zone: int = await input.select_zone(1, 0, [3, 5, 7], "destroy a zone", true)
	assert_int(zone).is_equal(5)
	assert_int(input.calls.size()).is_equal(1)
	assert_str(str(input.calls[0]["kind"])).is_equal("select_zone")
	assert_int(int(input.calls[0]["player_id"])).is_equal(1)
	assert_array(input.calls[0]["valid"]).contains_exactly([3, 5, 7])


# --- SignalPlayerInput ---

func test_signal_input_falls_back_when_unconnected() -> void:
	var input := SignalPlayerInput.new()
	assert_int(await input.choose_option(0, ["a", "b"], "p")).is_equal(0)
	assert_int(await input.select_zone(0, 1, [4], "p", false)).is_equal(4)
	# confirm_step with no listeners returns immediately (no hang).
	await input.confirm_step(0, "Draw", "auto_draw")


func test_signal_input_synchronous_resolve_during_emit() -> void:
	# A handler that answers during the request emit must not deadlock the await.
	var input := SignalPlayerInput.new()
	input.choice_requested.connect(func(_pid: int, _options: Array[String], _prompt: String) -> void:
		input.resolve_choice(1))
	assert_int(await input.choose_option(0, ["a", "b"], "p")).is_equal(1)
	assert_array(input.pending_kinds()).is_empty()


func test_signal_input_deferred_resolve() -> void:
	var input := SignalPlayerInput.new()
	input.zone_target_requested.connect(func(_pid: int, _tpid: int, _zones: Array[int], _prompt: String, _skip: bool) -> void:
		input.resolve_zone_target.call_deferred(7))
	assert_int(await input.select_zone(0, 1, [3, 7], "p", false)).is_equal(7)


func test_signal_input_confirmation_round_trip() -> void:
	var input := SignalPlayerInput.new()
	var seen: Array = []
	input.confirmation_requested.connect(func(prompt: String, setting: String) -> void:
		seen.append([prompt, setting])
		input.resolve_confirmation())
	await input.confirm_step(0, "Draw 2 card(s)", "auto_draw")
	assert_int(seen.size()).is_equal(1)
	assert_str(str(seen[0][1])).is_equal("auto_draw")


func test_signal_input_unsolicited_resolve_ignored() -> void:
	var input := SignalPlayerInput.new()
	input.resolve_choice(3)  # Nothing pending — must not crash or leave state behind.
	assert_array(input.pending_kinds()).is_empty()


func test_signal_input_hand_discard_round_trip() -> void:
	var input := SignalPlayerInput.new()
	input.hand_discard_requested.connect(func(_pid: int, _count: int) -> void:
		var picks: Array[int] = [0, 2]
		input.resolve_hand_discard(0, picks))
	assert_array(await input.choose_hand_discards(0, 2, 5)).contains_exactly([0, 2])


func test_signal_input_arrange_round_trip() -> void:
	var input := SignalPlayerInput.new()
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	input.deck_arrange_requested.connect(func(_pid: int, _cards: Array[Dictionary], _prompt: String) -> void:
		var keep: Array[Dictionary] = [b]
		var discard: Array[Dictionary] = [a]
		input.resolve_deck_arrange(keep, discard))
	var cards: Array[Dictionary] = [a, b]
	var result: Dictionary = await input.arrange_deck(0, cards, "p")
	assert_str(str(result["keep"][0].get("id"))).is_equal("B")
	assert_str(str(result["discard"][0].get("id"))).is_equal("A")
