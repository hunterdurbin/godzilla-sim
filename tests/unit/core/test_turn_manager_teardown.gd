extends GdUnitTestSuite

## TurnManager.teardown(): breaks the match's internal RefCounted reference
## cycles (EffectHandler <-> modules, ActionHandler <-> resolvers, cross-hub)
## so the engine graph is actually freed — leak regression for the
## "ObjectDB instances leaked at exit" shutdown noise.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_teardown_clears_hub_references() -> void:
	var state := States.make_state({})
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var eh: EffectHandler = tm.effect_handler
	var ah: ActionHandler = tm.action_handler

	tm.teardown()

	assert_object(tm.effect_handler).is_null()
	assert_object(tm.action_handler).is_null()
	assert_object(tm.player_input).is_null()
	assert_bool(tm.is_game_over).is_true()
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.GAME_OVER)
	# Hub back-references are broken
	assert_object(eh.action_handler).is_null()
	assert_object(eh.dispatcher).is_null()
	assert_object(ah.effect_handler).is_null()
	assert_object(ah.plays).is_null()


func test_teardown_frees_engine_graph() -> void:
	var state := States.make_state({})
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var eh_ref: WeakRef = weakref(tm.effect_handler)
	var ah_ref: WeakRef = weakref(tm.action_handler)
	var mover_ref: WeakRef = weakref(tm.effect_handler.mover)

	tm.teardown()

	# With the cycles broken, dropping the hub references frees the graph.
	assert_object(eh_ref.get_ref()).is_null()
	assert_object(ah_ref.get_ref()).is_null()
	assert_object(mover_ref.get_ref()).is_null()


func test_teardown_is_idempotent() -> void:
	var state := States.make_state({})
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())

	tm.teardown()
	tm.teardown()

	assert_object(tm.effect_handler).is_null()


func test_signal_player_input_ignores_late_resolves_after_teardown() -> void:
	var pin := SignalPlayerInput.new()
	pin.teardown()
	# Must not push warnings or resume anything — just a silent no-op.
	pin.resolve_confirmation()
	pin.resolve_choice(0)
	assert_array(pin.pending_kinds()).is_empty()
