extends GdUnitTestSuite

## DestructionEngine.destroy — the single destroy operation. The cause
## (effect / Crush / Overload) is its only behaviour switch:
##   - replacement effects (on_would_be_destroyed) apply for all three;
##   - destruction protection applies to effect destroys only (every
##     protecting card is worded "by your opponent's effects");
##   - <Revenge> fires for effect and Crush, never for Overload (12.7.2).
## The module moves the cards and returns the StandbyEntry objects the
## destruction triggered; the caller submits them.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

const Cause := DestructionEngine.Cause

const REVENGE := "test://destroy_revenge"
const REPLACE := "test://destroy_replace"
const PROTECTED := "test://destroy_cannot_be_destroyed"
const LEAVE := "test://destroy_leave"
const WATCHER := "test://destroy_ally_watcher"

## Target zone for every test: away from the default monster zone (1), so no
## crush rule action interferes.
const ZONE := 4


class RecordRevenge:
	extends CardEffect
	var seen: Array = []

	func on_revenge(ctx: EffectContext) -> void:
		seen.append("revenge:%s" % ctx.card_data.get("id"))


## <Destroy> replacement: moves to the deck bottom instead (EBP01-080 style).
class ReplaceDestroy:
	extends CardEffect

	func on_would_be_destroyed(_ctx: EffectContext) -> bool:
		return true


## Unconditional "cannot be <Destroy>".
class CannotBeDestroyed:
	extends CardEffect

	func can_be_destroyed(_ctx: EffectContext) -> bool:
		return false


class RecordLeave:
	extends CardEffect
	var seen: Array = []

	func on_leave_play(ctx: EffectContext, zone_index: int) -> void:
		seen.append("leave:%s:%d" % [ctx.card_data.get("id"), zone_index])


## Watches its owner's other battle cards being destroyed.
class RecordAllyDestroyed:
	extends CardEffect
	var seen: Array = []

	func on_ally_zone_card_destroyed(_ctx: EffectContext, destroyed_card: Dictionary, zone_idx: int) -> void:
		seen.append("ally_destroyed:%s:%d" % [destroyed_card.get("id"), zone_idx])


func _handler(state: GameState, input: PlayerInput = null) -> EffectHandler:
	var handler := EffectHandler.new()
	handler.setup(state, input if input else ScriptedPlayerInput.new())
	return handler


func _card(id: String, script_path: String) -> Dictionary:
	var c := Cards.battle(1, 5000, id)
	c["effect_script"] = script_path
	return c


func _state_with(card: Dictionary) -> GameState:
	return States.make_state({"p0": {"zone_cards": {ZONE: card}}})


func _resolve(handler: EffectHandler, outcome: DestructionEngine.Outcome) -> void:
	handler.check_timing.submit(outcome.entries)
	await handler.check_timing.resolve()


# --- Plain destroy ---

func test_destroy_moves_stack_to_discard_and_counts_as_destroyed() -> void:
	for cause: DestructionEngine.Cause in [Cause.EFFECT, Cause.CRUSH, Cause.OVERLOAD]:
		var card := Cards.battle(1, 5000, "PLAIN")
		var state := _state_with(card)
		var handler := _handler(state)
		var p0 := state.players[0]

		var outcome := handler.destruction.destroy(p0, ZONE, cause)

		assert_dict(outcome.card).is_equal(card)
		assert_bool(outcome.replaced).is_false()
		assert_bool(p0.zone_has_cards(ZONE)).is_false()
		assert_bool(p0.discard_pile.has(card)).is_true()
		assert_bool(p0.cards_destroyed_this_turn.has(card)).is_true()
		handler.teardown()


func test_destroy_empty_zone_is_a_no_op() -> void:
	var state := States.make_state()
	var handler := _handler(state)
	var outcome := handler.destruction.destroy(state.players[0], ZONE, Cause.EFFECT)
	assert_dict(outcome.card).is_empty()
	assert_array(outcome.entries).is_empty()
	handler.teardown()


# --- Replacement: all three causes ---

func test_replacement_applies_for_every_cause() -> void:
	for cause: DestructionEngine.Cause in [Cause.EFFECT, Cause.CRUSH, Cause.OVERLOAD]:
		var card := _card("REPL", REPLACE)
		var state := _state_with(card)
		var handler := _handler(state)
		handler.registry.register_for_test(REPLACE, ReplaceDestroy.new(), ["on_would_be_destroyed"])
		var p0 := state.players[0]

		var outcome := handler.destruction.destroy(p0, ZONE, cause)

		assert_bool(outcome.replaced).override_failure_message("cause %d" % cause).is_true()
		assert_bool(p0.zone_has_cards(ZONE)).is_false()
		assert_dict(p0.main_deck.back()).is_equal(card)
		assert_bool(p0.discard_pile.has(card)).is_false()
		assert_bool(p0.cards_destroyed_this_turn.has(card)).is_false()
		handler.teardown()


func test_replaced_card_still_triggers_leave_play_but_not_revenge() -> void:
	for cause: DestructionEngine.Cause in [Cause.EFFECT, Cause.CRUSH, Cause.OVERLOAD]:
		var card := _card("REPL", REPLACE)
		var state := _state_with(card)
		var handler := _handler(state)
		var effect := RecordLeaveReplaceRevenge.new()
		handler.registry.register_for_test(REPLACE, effect,
				["on_would_be_destroyed", "on_leave_play", "on_revenge"])

		await _resolve(handler, handler.destruction.destroy(state.players[0], ZONE, cause))

		assert_array(effect.seen).override_failure_message("cause %d" % cause) \
			.contains_exactly(["leave"])
		handler.teardown()


class RecordLeaveReplaceRevenge:
	extends CardEffect
	var seen: Array = []

	func on_would_be_destroyed(_ctx: EffectContext) -> bool:
		return true

	func on_leave_play(_ctx: EffectContext, _zone_index: int) -> void:
		seen.append("leave")

	func on_revenge(_ctx: EffectContext) -> void:
		seen.append("revenge")


# --- Protection: effect only ---

func test_protection_stops_an_effect_destroy() -> void:
	var card := _card("SAFE", PROTECTED)
	var state := _state_with(card)
	var handler := _handler(state)
	handler.registry.register_for_test(PROTECTED, CannotBeDestroyed.new(), ["can_be_destroyed"])
	var p0 := state.players[0]

	var outcome := handler.destruction.destroy(p0, ZONE, Cause.EFFECT)

	assert_dict(outcome.card).is_empty()
	assert_array(outcome.entries).is_empty()
	assert_dict(p0.get_zone_top_card(ZONE)).is_equal(card)
	handler.teardown()


func test_protection_does_not_stop_crush_or_overload() -> void:
	for cause: DestructionEngine.Cause in [Cause.CRUSH, Cause.OVERLOAD]:
		var card := _card("SAFE", PROTECTED)
		var state := _state_with(card)
		var handler := _handler(state)
		handler.registry.register_for_test(PROTECTED, CannotBeDestroyed.new(), ["can_be_destroyed"])
		var p0 := state.players[0]

		var outcome := handler.destruction.destroy(p0, ZONE, cause)

		assert_dict(outcome.card).override_failure_message("cause %d" % cause).is_equal(card)
		assert_bool(p0.discard_pile.has(card)).is_true()
		handler.teardown()


# --- <Revenge>: effect and Crush, never Overload ---

func test_revenge_fires_for_effect_and_crush() -> void:
	for cause: DestructionEngine.Cause in [Cause.EFFECT, Cause.CRUSH]:
		var card := _card("REV", REVENGE)
		var state := _state_with(card)
		var handler := _handler(state)
		var effect := RecordRevenge.new()
		handler.registry.register_for_test(REVENGE, effect, ["on_revenge"])

		await _resolve(handler, handler.destruction.destroy(state.players[0], ZONE, cause))

		assert_array(effect.seen).override_failure_message("cause %d" % cause) \
			.contains_exactly(["revenge:REV"])
		handler.teardown()


func test_revenge_never_fires_for_overload() -> void:
	var card := _card("REV", REVENGE)
	var state := _state_with(card)
	var handler := _handler(state)
	var effect := RecordRevenge.new()
	handler.registry.register_for_test(REVENGE, effect, ["on_revenge"])

	var outcome := handler.destruction.destroy(state.players[0], ZONE, Cause.OVERLOAD)
	await _resolve(handler, outcome)

	assert_array(outcome.entries).is_empty()
	assert_array(effect.seen).is_empty()
	handler.teardown()


func test_leave_play_entry_returned_for_every_cause() -> void:
	for cause: DestructionEngine.Cause in [Cause.EFFECT, Cause.CRUSH, Cause.OVERLOAD]:
		var card := _card("LEAVER", LEAVE)
		var state := _state_with(card)
		var handler := _handler(state)
		var effect := RecordLeave.new()
		handler.registry.register_for_test(LEAVE, effect, ["on_leave_play"])

		await _resolve(handler, handler.destruction.destroy(state.players[0], ZONE, cause))

		assert_array(effect.seen).override_failure_message("cause %d" % cause) \
			.contains_exactly(["leave:LEAVER:%d" % ZONE])
		handler.teardown()


# --- Zone-card-destroyed watchers: effect only (per-cause behaviour kept) ---

func test_ally_destroyed_watcher_fires_for_effect_only() -> void:
	var expected := {
		Cause.EFFECT: ["ally_destroyed:VICTIM:%d" % ZONE],
		Cause.CRUSH: [],
		Cause.OVERLOAD: [],
	}
	for cause: DestructionEngine.Cause in expected:
		var watcher := _card("WATCHER", WATCHER)
		var state := States.make_state({"p0": {"zone_cards": {
			ZONE: Cards.battle(1, 5000, "VICTIM"), ZONE + 1: watcher}}})
		var handler := _handler(state)
		var effect := RecordAllyDestroyed.new()
		handler.registry.register_for_test(WATCHER, effect, ["on_ally_zone_card_destroyed"])

		await _resolve(handler, handler.destruction.destroy(state.players[0], ZONE, cause))

		assert_array(effect.seen).override_failure_message("cause %d" % cause) \
			.contains_exactly(expected[cause])
		handler.teardown()


# --- Signals ---

func test_crush_emits_battle_card_crushed() -> void:
	var card := Cards.battle(1, 5000, "CRUSHED")
	var state := _state_with(card)
	var handler := _handler(state)
	handler.events = GameEvents.new()
	var crushed: Array = []
	handler.events.battle_card_crushed.connect(func(pid: int, z: int, c: Dictionary) -> void:
		crushed.append([pid, z, c.get("id")]))

	handler.destruction.destroy(state.players[0], ZONE, Cause.CRUSH)

	assert_array(crushed).contains_exactly([[0, ZONE, "CRUSHED"]])
	handler.teardown()


func test_effect_destroy_emits_card_destroyed() -> void:
	var state := _state_with(Cards.battle(1, 5000, "GONE"))
	var handler := _handler(state)
	var destroyed: Array = []
	handler.card_destroyed.connect(func(pid: int, z: int) -> void: destroyed.append([pid, z]))

	handler.destruction.destroy(state.players[0], ZONE, Cause.EFFECT)

	assert_array(destroyed).contains_exactly([[0, ZONE]])
	handler.teardown()


# --- Bot rank cap rides on the prompt request ---

func test_destroy_zone_and_adjacent_puts_rank_cap_on_the_zone_prompt() -> void:
	var state := States.make_state({"p1": {"zone_cards": {ZONE: Cards.battle(3, 5000, "BIG")}}})
	var input := ScriptedPlayerInput.new()
	var handler := _handler(state, input)

	await handler.destroy_zone_and_adjacent(0, state.players[1], [ZONE] as Array[int], "pick", 2)

	var calls := input.calls_of("select_zone")
	assert_int(calls.size()).is_equal(1)
	assert_int(calls[0]["max_rank"]).is_equal(2)
	# Rank 3 is over the cap: nothing destroyed.
	assert_bool(state.players[1].zone_has_cards(ZONE)).is_true()
	handler.teardown()
