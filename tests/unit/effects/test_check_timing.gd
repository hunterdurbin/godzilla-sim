extends GdUnitTestSuite

## CheckTiming (10.4.3): rule actions — crush (11.3) and illegal cards (11.4) —
## the standby pool (turn player first, order choice, abilities spawned
## mid-resolution), queueing behind a running ability, and the active-ability
## bookkeeping of run_effect.
##
## Built from a GameState + ScriptedPlayerInput + hand-made StandbyEntry
## objects; CheckTiming reaches the trigger collectors and the order prompt
## through a bare EffectHandler (no ActionHandler / session wiring).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _handler(state: GameState, input: PlayerInput = null) -> EffectHandler:
	var handler := EffectHandler.new()
	handler.setup(state, input if input else ScriptedPlayerInput.new())
	return handler


func _entry(player_id: int, card: Dictionary, callback: Callable) -> StandbyEntry:
	return StandbyEntry.new(player_id, card, callback)


# --- Rule actions ---

func test_crush_destroys_battle_card_under_monster() -> void:
	var state := States.make_state({"allow_illegal": true, "p0": {
		"monster_zone": 3,
		"zone_cards": {2: Cards.battle(1, 5000, "UNDER")},
	}})
	var ct := _handler(state).check_timing

	await ct.resolve()

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(state.players[0].cards_destroyed_this_turn.size()).is_equal(1)


func test_crush_checks_both_players_turn_player_first() -> void:
	var state := States.make_state({"allow_illegal": true, 
		"current_player_id": 1,
		"p0": {"monster_zone": 2, "zone_cards": {1: Cards.battle(1, 5000, "P0")}},
		"p1": {"monster_zone": 5, "zone_cards": {4: Cards.battle(1, 5000, "P1")}},
	})
	var handler := _handler(state)
	handler.events = GameEvents.new()
	var crush_order: Array = []
	handler.events.battle_card_crushed.connect(func(pid: int, _z: int, _c: Dictionary) -> void:
		crush_order.append(pid))

	await handler.check_timing.resolve()

	# Turn player (1) crushes first (11.1.2.1.1).
	assert_array(crush_order).contains_exactly([1, 0])


func test_no_crush_when_zone_clear() -> void:
	var state := States.make_state({"p0": {
		"monster_zone": 3,
		"zone_cards": {4: Cards.battle(1, 5000, "ELSEWHERE")},
	}})
	await _handler(state).check_timing.resolve()
	assert_bool(state.players[0].zone_has_cards(4)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_crush_now_crushes_only_the_named_player() -> void:
	var state := States.make_state({"allow_illegal": true, 
		"p0": {"monster_zone": 2, "zone_cards": {1: Cards.battle(1, 5000, "P0")}},
		"p1": {"monster_zone": 5, "zone_cards": {4: Cards.battle(1, 5000, "P1")}},
	})
	_handler(state).check_timing.crush_now(1)
	assert_bool(state.players[0].zone_has_cards(1)).is_true()
	assert_bool(state.players[1].zone_has_cards(4)).is_false()


func test_illegal_strategy_in_zone_discarded() -> void:
	var state := States.make_state({"p0": {
		"zone_cards": {4: Cards.strategy(1, "ILLEGAL")},
	}})
	await _handler(state).check_timing.resolve()
	assert_bool(state.players[0].zone_has_cards(4)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_illegal_battle_card_in_strategy_zone_discarded() -> void:
	var state := States.make_state({"p0": {
		"strategy_zones": [Cards.battle(1, 5000, "WRONG-SLOT")],
	}})
	await _handler(state).check_timing.resolve()
	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


# --- Standby pool ---

func test_submit_only_queues_until_the_check_timing() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var ran: Array = []
	ct.submit([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	# Submitting never resolves on the spot (10.6.2): the ability waits in
	# standby for the next check timing.
	assert_int(ran.size()).is_equal(0)
	assert_bool(ct.has_pending()).is_true()

	await ct.resolve()
	assert_int(ran.size()).is_equal(1)
	assert_bool(ct.has_pending()).is_false()


func test_turn_player_resolves_first() -> void:
	var state := States.make_state({"current_player_id": 1})
	var ct := _handler(state).check_timing
	var order: Array = []
	ct.submit([
		_entry(0, Cards.battle(1, 5000, "P0-CARD"), func() -> void: order.append("p0")),
		_entry(1, Cards.battle(1, 5000, "P1-CARD"), func() -> void: order.append("p1")),
	])
	await ct.resolve()
	# Player 1 is the turn player -> their ability resolves first.
	assert_array(order).contains_exactly(["p1", "p0"])


func test_multiple_abilities_prompt_order_choice() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}  # pick the second listed ability first
	var ct := _handler(state, input).check_timing
	var order: Array = []
	ct.submit([
		_entry(0, Cards.battle(1, 5000, "A"), func() -> void: order.append("a")),
		_entry(0, Cards.battle(1, 5000, "B"), func() -> void: order.append("b")),
	])
	await ct.resolve()
	assert_array(order).contains_exactly(["b", "a"])
	# The order prompt fired exactly once (second round has a single entry left).
	assert_int(input.count_calls("choose_option")).is_equal(1)


func test_single_ability_no_prompt() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	var ct := _handler(state, input).check_timing
	var ran: Array = []
	ct.submit([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	await ct.resolve()
	assert_int(ran.size()).is_equal(1)
	assert_int(input.count_calls("choose_option")).is_equal(0)


func test_entries_submitted_mid_resolution_join_the_pool() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var order: Array = []
	var spawner := func() -> void:
		order.append("first")
		# Abilities triggered while another resolves queue behind it.
		ct.submit([_entry(0, Cards.battle(1, 5000, "SPAWNED"), func() -> void: order.append("spawned"))])
		order.append("first-done")
	ct.submit([_entry(0, Cards.battle(1, 5000, "FIRST"), spawner)])
	await ct.resolve()
	assert_array(order).contains_exactly(["first", "first-done", "spawned"])


func test_still_applies_false_drops_entry() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var ran: Array = []
	ct.submit([
		StandbyEntry.new(0, Cards.battle(1, 5000, "GONE"), func() -> void: ran.append("gone"),
				func() -> bool: return false),
		StandbyEntry.new(0, Cards.battle(1, 5000, "KEPT"), func() -> void: ran.append("kept"),
				func() -> bool: return true),
	])
	await ct.resolve()
	assert_array(ran).contains_exactly(["kept"])


func test_ability_resolves_after_its_card_changes_areas() -> void:
	# 10.6.7: an ability in standby is still played even if its card has
	# changed areas since it triggered — no "still in play" filter.
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var ct := _handler(state, input).check_timing
	var on_field := Cards.battle(1, 5000, "ON-FIELD")
	state.players[0].push_zone_card(2, on_field)
	var gone := Cards.battle(1, 5000, "GONE")
	state.players[0].discard_pile.append(gone)
	var ran: Array = []
	ct.submit([
		_entry(0, on_field, func() -> void: ran.append("on_field")),
		_entry(0, gone, func() -> void: ran.append("gone")),
	])
	await ct.resolve()
	assert_array(ran).contains_exactly_in_any_order(["on_field", "gone"])


# --- One pool per check timing (real trigger sources) ---

const RECORDER := "test://check_timing_recorder"


## One shared instance (as the registry shares effects per script path):
## records which hook ran on which card, and whether zone idx 0 — the turn
## player's monster zone — still held a battle card when an <Enter> resolved.
class Recorder:
	extends CardEffect
	var seen: Array = []

	func on_enter(ctx: EffectContext) -> void:
		seen.append("enter:%s:crushed=%s" % [ctx.card_data["id"], not ctx.owner.zone_has_cards(0)])

	func on_leave_play(ctx: EffectContext, _zone_index: int) -> void:
		seen.append("leave:%s" % ctx.card_data["id"])

	func on_battle_card_played(ctx: EffectContext, _zone_index: int, _played_from_deck: bool = false) -> void:
		seen.append("played:%s" % ctx.card_data["id"])

	func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
		seen.append("advance:%s" % ctx.card_data["id"])


func _recorded(id: String) -> Dictionary:
	var card := Cards.battle(1, 5000, id)
	card["effect_script"] = RECORDER
	return card


func _recorder_session(state: GameState, input: ScriptedPlayerInput, triggers: Array) -> Dictionary:
	var s := States.make_session(state, input)
	var effect := Recorder.new()
	(s["effect_handler"] as EffectHandler).registry.register_for_test(RECORDER, effect, triggers)
	s["recorder"] = effect
	return s


func test_one_plays_triggers_share_one_pool_turn_player_first() -> void:
	# Turn player 0 plays NEW over OLD (overload → OLD's leave-play), NEW has
	# <Enter>, and both players' watchers see the play. A battle card sitting
	# in player 0's monster zone is crushed by the check timing's rule
	# actions before any ability resolves (10.4.3.1).
	var state := States.make_state({"allow_illegal": true, 
		"current_player_id": 0,
		"p0": {"hand": [_recorded("NEW")], "zone_cards": {
			0: Cards.battle(1, 5000, "CRUSHED"), 3: _recorded("OLD"), 5: _recorded("OWN-WATCH")}},
		"p1": {"monster_zone": 8, "zone_cards": {4: _recorded("OPP-WATCH")}},
	})
	var input := ScriptedPlayerInput.new()
	# Player 0's pool, in submission order: OLD leave-play, NEW <Enter>,
	# OWN-WATCH played. Pick <Enter> (1), then the watcher (1 of the 2 left).
	input.answers = {"choose_option": [1, 1]}
	var s := _recorder_session(state, input, ["on_enter", "on_leave_play", "on_battle_card_played"])
	var recorder: Recorder = s["recorder"]
	var handler: EffectHandler = s["effect_handler"]

	await s["action_handler"].execute(CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 3}, state)

	# The play itself resolves nothing: every ability waits in standby.
	assert_array(recorder.seen).is_empty()

	await handler.check_timing.resolve() # 10.4.4.1

	assert_array(recorder.seen).contains_exactly([
		"enter:NEW:crushed=true",
		"played:OWN-WATCH",
		"leave:OLD",
		"played:OPP-WATCH",  # non-turn player's ability only once player 0 has none
	])
	# Player 0 chose twice among their own abilities; player 1 had one, no prompt.
	var choosers: Array = input.calls_of("choose_option").map(
		func(c: Dictionary) -> int: return c["player_id"])
	assert_array(choosers).contains_exactly([0, 0])
	assert_bool(handler.check_timing.has_pending()).is_false()


func test_crushed_cards_advance_ability_still_resolves() -> void:
	# 10.6.7: the monster advances onto ADV, which triggers on the advance;
	# the same movement crushes ADV, and its ability still resolves.
	var state := States.make_state({"p0": {"monster_zone": 2, "zone_cards": {2: _recorded("ADV")}}})
	var s := _recorder_session(state, ScriptedPlayerInput.new(), ["on_monster_advance"])
	var recorder: Recorder = s["recorder"]
	var handler: EffectHandler = s["effect_handler"]

	handler.advance_monster_to_zone(0, 3)
	await handler.check_timing.resolve()

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_str(str(state.players[0].discard_pile.back().get("id"))).is_equal("ADV")
	assert_array(recorder.seen).contains_exactly(["advance:ADV"])


# --- Running an ability ---

func test_run_effect_marks_active_and_queues_submissions() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var ran: Array = []
	var seen_active: Array = []
	await ct.run_effect(0, Cards.battle(1, 5000, "ACTIVE"), func() -> void:
		seen_active.append(ct.active_card.get("id", ""))
		ct.submit([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
		# Queued, not run, while the ability resolves.
		seen_active.append(ran.size()))
	assert_array(seen_active).contains_exactly(["ACTIVE", 0])
	assert_bool(ct.has_active_effect()).is_false()
	assert_bool(ct.has_pending()).is_true()

	await ct.resolve()
	assert_int(ran.size()).is_equal(1)
	assert_bool(ct.has_pending()).is_false()


func test_run_effect_restores_the_outer_ability() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var seen: Array = []
	await ct.run_effect(1, Cards.battle(1, 5000, "OUTER"), func() -> void:
		await ct.run_effect(0, Cards.battle(1, 5000, "INNER"), func() -> void:
			seen.append("%d:%s" % [ct.active_player_id, ct.active_card.get("id", "")]))
		seen.append("%d:%s" % [ct.active_player_id, ct.active_card.get("id", "")]))
	assert_array(seen).contains_exactly(["0:INNER", "1:OUTER"])
	assert_int(ct.active_player_id).is_equal(-1)


func test_standby_callback_runs_as_the_active_ability() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	var seen: Array = []
	ct.submit([_entry(0, Cards.battle(1, 5000, "ABILITY"), func() -> void:
		seen.append(ct.active_card.get("id", "")))])
	await ct.resolve()
	# During the callback the entry's card was active; afterwards cleared.
	assert_array(seen).contains_exactly(["ABILITY"])
	assert_bool(ct.has_active_effect()).is_false()


# --- Card location refs ---

func test_card_location_label() -> void:
	var state := States.make_state({"p0": {"monster_zone": 1}})
	var zone_card := Cards.battle(1, 5000, "Z")
	zone_card["name"] = "Zone Dweller"
	state.players[0].push_zone_card(4, zone_card)
	assert_str(CheckTiming.card_location_label(state, 0, zone_card)).is_equal("Zone Dweller (Zone 5)")
	var monster: Dictionary = state.players[0].current_monster
	assert_str(CheckTiming.card_location_label(state, 0, monster)).contains("(Monster)")


func test_card_location_ref_kinds() -> void:
	var strat := Cards.strategy(1, "S")
	var state := States.make_state({"p0": {"monster_zone": 1, "strategy_zones": [strat]}})
	var zone_card := Cards.battle(1, 5000, "Z")
	state.players[0].push_zone_card(4, zone_card)
	var discarded := Cards.battle(1, 5000, "D")
	state.players[0].discard_pile.append(discarded)

	var zref := CheckTiming.card_location_ref(state, 0, zone_card)
	assert_str(zref["kind"]).is_equal("zone")
	assert_int(zref["index"]).is_equal(4)
	assert_str(zref["instance_id"]).is_equal("Z")
	assert_int(zref["player_id"]).is_equal(0)
	assert_str(zref["label"]).is_equal(zone_card["name"] + " (Zone 5)")

	var mref := CheckTiming.card_location_ref(state, 0, state.players[0].current_monster)
	assert_str(mref["kind"]).is_equal("monster")
	assert_str(mref["label"]).contains("(Monster)")

	var sref := CheckTiming.card_location_ref(state, 0, strat)
	assert_str(sref["kind"]).is_equal("strategy")
	assert_int(sref["index"]).is_equal(0)

	var dref := CheckTiming.card_location_ref(state, 0, discarded)
	assert_str(dref["kind"]).is_equal("discard")

	# The marker scan must not leave residue on the card dicts.
	assert_bool(zone_card.has("__ref_marker")).is_false()


func test_card_location_ref_finds_covered_zone_card() -> void:
	# A standby ability whose card was evolved over still resolves (10.6.7);
	# the stack UI must still locate the card underneath.
	var state := States.make_state()
	var under := Cards.battle(6, 5000, "UNDER")
	under["name"] = "Flying"
	var top := Cards.battle(8, 5000, "TOP")
	state.players[0].push_zone_card(2, under)
	state.players[0].push_zone_card(2, top)

	var ref := CheckTiming.card_location_ref(state, 0, under)
	assert_str(ref["kind"]).is_equal("zone")
	assert_int(ref["index"]).is_equal(2)
	assert_bool(ref.get("covered", false)).is_true()
	assert_str(ref["label"]).is_equal("Flying (Zone 3, covered)")
	assert_bool(CheckTiming.card_location_ref(state, 0, top).get("covered", false)).is_false()
	assert_bool(under.has("__ref_marker")).is_false()


func test_card_location_ref_disambiguates_duplicate_ids() -> void:
	var state := States.make_state()
	var a := Cards.battle(1, 5000, "DUP")
	var b := Cards.battle(1, 5000, "DUP")
	state.players[0].push_zone_card(1, a)
	state.players[0].push_zone_card(6, b)
	assert_int(CheckTiming.card_location_ref(state, 0, a)["index"]).is_equal(1)
	assert_int(CheckTiming.card_location_ref(state, 0, b)["index"]).is_equal(6)


# --- Order prompt side channels + stack notifications ---

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
	var handler := _handler(state, input)
	input.handler = handler
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	# Zone 1 holds the monster (a check timing would crush a card there).
	state.players[0].push_zone_card(1, a)
	state.players[0].push_zone_card(3, b)
	handler.check_timing.submit([
		_entry(0, a, func() -> void: pass),
		_entry(0, b, func() -> void: pass),
	])
	await handler.check_timing.resolve()
	# During the order prompt the refs paralleled the options...
	assert_int(input.snapshot.size()).is_equal(2)
	assert_str(input.snapshot[0]["kind"]).is_equal("zone")
	assert_int(input.snapshot[0]["index"]).is_equal(1)
	assert_int(input.snapshot[1]["index"]).is_equal(3)
	# ...and were cleared once the choice resolved.
	assert_int(handler.choice_source_refs.size()).is_equal(0)


func test_effect_stack_changed_emission_sequence() -> void:
	var state := States.make_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [0]}
	var handler := _handler(state, input)
	handler.events = GameEvents.new()
	var snapshots: Array = []
	handler.events.effect_stack_changed.connect(func(stack: Array) -> void:
		snapshots.append(stack.duplicate(true)))
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	state.players[0].push_zone_card(1, a)
	state.players[0].push_zone_card(3, b)
	handler.check_timing.submit([
		_entry(0, a, func() -> void: pass),
		_entry(0, b, func() -> void: pass),
	])
	await handler.check_timing.resolve()
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


func test_effect_stack_publishes_when_queued() -> void:
	var state := States.make_state()
	var handler := _handler(state)
	handler.events = GameEvents.new()
	var snapshots: Array = []
	handler.events.effect_stack_changed.connect(func(stack: Array) -> void:
		snapshots.append(stack.duplicate(true)))
	var ct := handler.check_timing
	await ct.run_effect(0, Cards.battle(1, 5000, "ACTIVE"), func() -> void:
		ct.submit([_entry(0, Cards.battle(1, 5000, "Q"), func() -> void: pass)]))
	# Queued entries publish immediately so the stack UI shows them.
	assert_int(snapshots.size()).is_equal(1)
	assert_int((snapshots[0] as Array).size()).is_equal(1)
	assert_str(snapshots[0][0]["status"]).is_equal("pending")


func test_no_stack_emission_without_events_bus() -> void:
	var state := States.make_state()
	var ct := _handler(state).check_timing
	# events stays null (bare test wiring) — resolving must not crash.
	var ran: Array = []
	ct.submit([_entry(0, Cards.battle(1), func() -> void: ran.append(1))])
	await ct.resolve()
	assert_int(ran.size()).is_equal(1)
