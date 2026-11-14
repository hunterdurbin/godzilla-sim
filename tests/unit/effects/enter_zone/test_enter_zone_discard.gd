extends GdUnitTestSuite

## EnterZone, discard source: an effect plays a battle card from the discard
## pile. It leaves the pile, overloads the zone and fires <Enter> as an
## effect play. Current behaviour, pinned: the "when played" watchers do not
## fire for it yet (the next ticket adds them).

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


func test_a_discard_play_leaves_the_pile_overloads_and_fires_enter() -> void:
	var card := Probe.card("NEW")
	var s := _setup({"zone_cards": {ZONE: Probe.card("OLD")}})
	var p0: PlayerState = s["state"].players[0]
	p0.discard_pile.append(card)

	assert_bool(_enter(s, card, ZONE, Source.DISCARD)).is_true()

	assert_bool(p0.discard_pile.has(card)).is_false()
	assert_dict(p0.get_zone_top_card(ZONE)).is_equal(card)
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
			"leave:OLD:%d" % ZONE, "enter:NEW:effect=true:evo=false"])
	_teardown(s)


func test_a_refused_discard_card_stays_in_the_pile() -> void:
	var card := Probe.card("NEW")
	var s := _setup()
	var p0: PlayerState = s["state"].players[0]
	p0.discard_pile.append(card)

	assert_bool(_enter(s, card, MONSTER_ZONE_IDX, Source.DISCARD)).is_false()

	assert_array(p0.discard_pile).contains_exactly([card])
	assert_array(await _resolve(s)).is_empty()
	_teardown(s)
