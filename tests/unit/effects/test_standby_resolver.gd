extends GdUnitTestSuite

## StandbyResolver tests: rule 10.4.3 ordering, order choice via PlayerInput,
## mid-resolution spawned entries, and re-entrancy deferral.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _make_handler(state: GameState, input: PlayerInput) -> EffectHandler:
	var handler := EffectHandler.new()
	handler.setup(state, input)
	return handler


func _entry(player_id: int, card: Dictionary, callback: Callable) -> Dictionary:
	return {"player_id": player_id, "card_data": card, "callback": callback}


func test_turn_player_resolves_first() -> void:
	var state := States.make_state({"current_player_id": 1})
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	var order: Array = []
	var entries := [
		_entry(0, Cards.battle(1, 5000, "P0-CARD"), func() -> void: order.append("p0")),
		_entry(1, Cards.battle(1, 5000, "P1-CARD"), func() -> void: order.append("p1")),
	]
	await handler.standby.resolve_entries(entries)
	# Player 1 is the turn player -> their ability resolves first.
	assert_array(order).contains_exactly(["p1", "p0"])


func test_multiple_abilities_prompt_order_choice() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}  # pick the second listed ability first
	var handler := _make_handler(state, input)
	var order: Array = []
	var entries := [
		_entry(0, Cards.battle(1, 5000, "A"), func() -> void: order.append("a")),
		_entry(0, Cards.battle(1, 5000, "B"), func() -> void: order.append("b")),
	]
	await handler.standby.resolve_entries(entries)
	assert_array(order).contains_exactly(["b", "a"])
	# The order prompt fired exactly once (second round has a single entry left).
	assert_int(input.count_calls("choose_option")).is_equal(1)


func test_single_ability_no_prompt() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	var handler := _make_handler(state, input)
	var ran: Array = []
	await handler.standby.resolve_entries([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	assert_int(ran.size()).is_equal(1)
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_entries_spawned_mid_resolution_drain() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	var order: Array = []
	var spawner := func() -> void:
		order.append("first")
		# Effects triggered while another effect resolves defer to the queue.
		handler.exec.pending_standby_entries.append(
			_entry(0, Cards.battle(1, 5000, "SPAWNED"), func() -> void: order.append("spawned")))
	await handler.standby.resolve_entries([_entry(0, Cards.battle(1, 5000, "FIRST"), spawner)])
	assert_array(order).contains_exactly(["first", "spawned"])


func test_resolve_defers_when_effect_active() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	# Simulate an actively executing effect.
	handler.exec.set_active(0, Cards.battle(1, 5000, "ACTIVE"))
	var ran: Array = []
	await handler.standby.resolve_entries([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	# Deferred, not run.
	assert_int(ran.size()).is_equal(0)
	assert_int(handler.exec.pending_standby_entries.size()).is_equal(1)
	handler.exec.clear_active()


func test_resolve_deferred_entries_filters_inactive_cards() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	var on_field := Cards.battle(1, 5000, "ON-FIELD")
	state.players[0].push_zone_card(2, on_field)
	var gone := Cards.battle(1, 5000, "GONE")
	var ran: Array = []
	await handler.standby.resolve_deferred_entries([
		_entry(0, on_field, func() -> void: ran.append("on_field")),
		_entry(0, gone, func() -> void: ran.append("gone")),
		{"player_id": 0, "card_data": gone, "callback": func() -> void: ran.append("skip_check"), "skip_active_check": true},
	])
	assert_array(ran).contains_exactly(["on_field", "skip_check"])


func test_active_effect_saved_and_restored_around_callbacks() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	var seen: Array = []
	var card := Cards.battle(1, 5000, "ABILITY")
	await handler.standby.resolve_entries([_entry(0, card, func() -> void:
		seen.append(handler.exec.active_card.get("id", "")))])
	# During the callback the entry's card was active; afterwards cleared.
	assert_array(seen).contains_exactly(["ABILITY"])
	assert_bool(handler.exec.has_active_effect()).is_false()


func test_card_location_label() -> void:
	var state := States.make_state({"p0": {"monster_zone": 1}})
	var zone_card := Cards.battle(1, 5000, "Z")
	zone_card["name"] = "Zone Dweller"
	state.players[0].push_zone_card(4, zone_card)
	assert_str(StandbyResolver.card_location_label(state, 0, zone_card)).is_equal("Zone Dweller (Zone 5)")
	var monster: Dictionary = state.players[0].current_monster
	assert_str(StandbyResolver.card_location_label(state, 0, monster)).contains("(Monster)")
