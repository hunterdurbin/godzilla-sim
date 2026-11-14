extends GdUnitTestSuite

## Every ActionHandler builder wires `rules_engine` to the RulesEngine its
## match validates with: CounterResolver asks it for the counter numbers and
## rank-up candidates, and an unwired handler crashes in the counter phase.
## A new builder belongs in this suite.

const States := preload("res://tests/fixtures/states.gd")


func test_match_factory_wires_rules_engine() -> void:
	var tm := TurnManager.new()
	MatchFactory.setup_from_save(tm, {})
	assert_object(tm.rules_engine).is_not_null()
	assert_object(tm.action_handler.rules_engine).is_same(tm.rules_engine)
	tm.teardown()


func test_make_session_wires_rules_engine() -> void:
	var session := States.make_session(States.make_state())
	var action_handler: ActionHandler = session["action_handler"]
	assert_object(action_handler.rules_engine).is_same(session["rules"])
	action_handler.teardown()
	(session["effect_handler"] as EffectHandler).teardown()


func test_max_counter_state_wires_rules_engine() -> void:
	var mcs := MaxCounterState.new([] as Array[Dictionary], [] as Array[Dictionary])
	assert_object(mcs.rules_engine).is_not_null()
	assert_object(mcs.action_handler.rules_engine).is_same(mcs.rules_engine)
	mcs.teardown()
