extends GdUnitTestSuite

## EnterZone.move_stack: a zone's whole stack moves to another zone. It
## overloads the destination, and the moved card stays in play, so it fires
## on_zone_changed (EBP04-067 link) and no <Enter> or "when played".

const States := preload("res://tests/fixtures/states.gd")
const Probe := preload("res://tests/fixtures/effects/enter_zone_probe.gd")

const Source := EnterZone.Source

const MONSTER_ZONE_IDX := 3  # p0's monster in zone 4
const ZONE := 5
const WATCH_ZONE := 0


## p0 with its monster in zone 4 and a probe watcher in zone 1.
func _setup(p0: Dictionary = {}) -> Dictionary:
	var p0_opts: Dictionary = {"monster_zone": MONSTER_ZONE_IDX + 1,
			"zone_cards": {WATCH_ZONE: Probe.card("WATCH")}}
	for key: String in p0:
		if key == "zone_cards":
			p0_opts["zone_cards"].merge(p0[key])
		else:
			p0_opts[key] = p0[key]
	var state := States.make_state({"p0": p0_opts})
	var s := States.make_session(state)
	s["state"] = state
	s["probe"] = Probe.register(s["effect_handler"])
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


func _enter(s: Dictionary, card: Dictionary, zone: int, source: EnterZone.Source,
		stack_on_top: bool = false) -> bool:
	var handler: EffectHandler = s["effect_handler"]
	return handler.enter_zone.enter(0, card, zone, source, true, stack_on_top)


## Resolve the check timing and return what the probe saw.
func _resolve(s: Dictionary) -> Array:
	var handler: EffectHandler = s["effect_handler"]
	await handler.check_timing.resolve()
	return s["probe"].seen


func test_a_stack_moves_overloads_the_destination_and_fires_zone_changed() -> void:
	var top := Probe.card("TOP")
	var under := Probe.card("UNDER")
	var s := _setup({"zone_cards": {ZONE: Probe.card("OLD"), 1: top}})
	var p0: PlayerState = s["state"].players[0]
	p0.zones[1].append(under)

	assert_bool(s["effect_handler"].enter_zone.move_stack(0, 1, ZONE)).is_true()

	assert_bool(p0.zone_has_cards(1)).is_false()
	assert_array(p0.zones[ZONE]).contains_exactly([top, under])
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
			"leave:OLD:%d" % ZONE, "moved:TOP:1>%d" % ZONE])
	_teardown(s)


func test_moving_an_empty_zone_or_onto_itself_does_nothing() -> void:
	var top := Probe.card("TOP")
	var s := _setup({"zone_cards": {1: top}})

	assert_bool(s["effect_handler"].enter_zone.move_stack(0, 2, ZONE)).is_false()
	assert_bool(s["effect_handler"].enter_zone.move_stack(0, 1, 1)).is_false()

	assert_array(s["state"].players[0].zones[1]).contains_exactly([top])
	assert_array(await _resolve(s)).is_empty()
	_teardown(s)
