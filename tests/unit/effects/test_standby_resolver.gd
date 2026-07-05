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


func test_card_location_ref_kinds() -> void:
	var strat := Cards.strategy(1, "S")
	var state := States.make_state({"p0": {"monster_zone": 1, "strategy_zones": [strat]}})
	var zone_card := Cards.battle(1, 5000, "Z")
	state.players[0].push_zone_card(4, zone_card)
	var discarded := Cards.battle(1, 5000, "D")
	state.players[0].discard_pile.append(discarded)

	var zref := StandbyResolver.card_location_ref(state, 0, zone_card)
	assert_str(zref["kind"]).is_equal("zone")
	assert_int(zref["index"]).is_equal(4)
	assert_str(zref["instance_id"]).is_equal("Z")
	assert_int(zref["player_id"]).is_equal(0)
	assert_str(zref["label"]).is_equal(zone_card["name"] + " (Zone 5)")

	var mref := StandbyResolver.card_location_ref(state, 0, state.players[0].current_monster)
	assert_str(mref["kind"]).is_equal("monster")
	assert_str(mref["label"]).contains("(Monster)")

	var sref := StandbyResolver.card_location_ref(state, 0, strat)
	assert_str(sref["kind"]).is_equal("strategy")
	assert_int(sref["index"]).is_equal(0)

	var dref := StandbyResolver.card_location_ref(state, 0, discarded)
	assert_str(dref["kind"]).is_equal("discard")

	# The marker scan must not leave residue on the card dicts.
	assert_bool(zone_card.has("__ref_marker")).is_false()


func test_card_location_ref_disambiguates_duplicate_ids() -> void:
	var state := States.make_state()
	var a := Cards.battle(1, 5000, "DUP")
	var b := Cards.battle(1, 5000, "DUP")
	state.players[0].push_zone_card(1, a)
	state.players[0].push_zone_card(6, b)
	assert_int(StandbyResolver.card_location_ref(state, 0, a)["index"]).is_equal(1)
	assert_int(StandbyResolver.card_location_ref(state, 0, b)["index"]).is_equal(6)


class RefSnapshotInput extends ScriptedPlayerInput:
	## Snapshots the handler's choice_source_refs side-channel at prompt time,
	## the way the live choice UI reads it.
	var handler: EffectHandler
	var snapshot: Array = []

	func choose_option(player_id: int, options: Array[String], prompt: String) -> int:
		if handler:
			snapshot = handler.choice_source_refs.duplicate(true)
		return super(player_id, options, prompt)


func test_choice_source_refs_populated_and_cleared() -> void:
	var state := States.make_state()
	var input := RefSnapshotInput.new()
	input.answers = {"choose_option": [0]}
	var handler := _make_handler(state, input)
	input.handler = handler
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	state.players[0].push_zone_card(0, a)
	state.players[0].push_zone_card(3, b)
	await handler.standby.resolve_entries([
		_entry(0, a, func() -> void: pass),
		_entry(0, b, func() -> void: pass),
	])
	# During the order prompt the refs paralleled the options...
	assert_int(input.snapshot.size()).is_equal(2)
	assert_str(input.snapshot[0]["kind"]).is_equal("zone")
	assert_int(input.snapshot[0]["index"]).is_equal(0)
	assert_int(input.snapshot[1]["index"]).is_equal(3)
	# ...and were cleared once the choice resolved.
	assert_int(handler.choice_source_refs.size()).is_equal(0)


func test_effect_stack_changed_emission_sequence() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var handler := _make_handler(state, input)
	handler.events = GameEvents.new()
	var snapshots: Array = []
	handler.events.effect_stack_changed.connect(func(stack: Array) -> void:
		snapshots.append(stack.duplicate(true)))
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	state.players[0].push_zone_card(0, a)
	state.players[0].push_zone_card(3, b)
	await handler.standby.resolve_entries([
		_entry(0, a, func() -> void: pass),
		_entry(0, b, func() -> void: pass),
	])
	assert_bool(snapshots.size() >= 3).is_true()
	# Some publish showed the whole batch pending (during the order prompt),
	# some publish marked exactly one entry as resolving, and the final
	# publish is the drained (empty) stack.
	var had_two_pending := false
	var had_one_resolving := false
	for snap in snapshots:
		var pending := 0
		var resolving := 0
		for row in snap:
			if row["status"] == "pending":
				pending += 1
			elif row["status"] == "resolving":
				resolving += 1
		if pending == 2 and resolving == 0:
			had_two_pending = true
		if resolving == 1:
			had_one_resolving = true
	assert_bool(had_two_pending).is_true()
	assert_bool(had_one_resolving).is_true()
	assert_int((snapshots.back() as Array).size()).is_equal(0)


func test_effect_stack_publishes_on_deferral() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	handler.events = GameEvents.new()
	var snapshots: Array = []
	handler.events.effect_stack_changed.connect(func(stack: Array) -> void:
		snapshots.append(stack.duplicate(true)))
	handler.exec.set_active(0, Cards.battle(1, 5000, "ACTIVE"))
	await handler.standby.resolve_entries([
		_entry(0, Cards.battle(1, 5000, "Q"), func() -> void: pass)])
	# Deferred entries publish immediately so the stack UI shows them.
	assert_int(snapshots.size()).is_equal(1)
	assert_int((snapshots[0] as Array).size()).is_equal(1)
	assert_str(snapshots[0][0]["status"]).is_equal("pending")
	handler.exec.clear_active()


func test_no_stack_emission_without_events_bus() -> void:
	var state := States.make_state()
	var handler := _make_handler(state, ScriptedPlayerInput.new())
	# events stays null (bare test wiring) — resolving must not crash.
	var ran: Array = []
	await handler.standby.resolve_entries([
		_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	assert_int(ran.size()).is_equal(1)
