extends GdUnitTestSuite

## EnterZone, evolution source: Evolve makes a battle card appear on top of
## the zone's battle card (5.17). It never overloads, has no legality check,
## marks the <Enter> as through evolution, and fires the "when played"
## watchers with played_from_deck = true (the card came from the deck).

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


func test_evolve_stacks_on_top_and_fires_enter_through_evolution() -> void:
	var under := Probe.card("BASE")
	under["evolution_rank"] = 3
	var s := _setup({"zone_cards": {ZONE: under}})
	var card := Probe.card("EVO", 3)
	var handler: EffectHandler = s["effect_handler"]
	var evolved: Array = []
	handler.card_evolved.connect(func(pid: int, c: Dictionary, z: int) -> void:
		evolved.append([pid, c.get("id"), z]))

	assert_bool(_enter(s, card, ZONE, Source.EVOLUTION)).is_true()

	assert_array(s["state"].players[0].zones[ZONE]).contains_exactly([card, under])
	assert_array(evolved).contains_exactly([[0, "EVO", ZONE]])
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
			"enter:EVO:effect=true:evo=true", "played@WATCH:%d:deck=true" % ZONE])
	_teardown(s)
