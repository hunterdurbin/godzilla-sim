extends GdUnitTestSuite

## EnterZone, evolution source: Evolve plays a battle card from the deck on
## top of the zone's battle card (5.17.1 "重ねて出現させます"; Q176
## "山札から…重ねて出現させる"). It never overloads, marks the <Enter> as
## through evolution, fires the "when played" watchers with
## played_from_deck = true, and is refused where any play is (the monster's
## zone, 5.11.1.1; the opponent's block, Q270).

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


func test_evolve_stacks_on_top_and_fires_enter_and_played_from_deck() -> void:
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


func test_an_evolve_refused_in_the_monster_zone_goes_back_on_the_deck() -> void:
	var under := Probe.card("BASE")
	var s := _setup()
	var card := Probe.card("EVO", 3)
	var p0: PlayerState = s["state"].players[0]
	# Set after setup: make_state refuses a battle card in the monster's
	# zone (the next check timing would crush it, 11.3).
	p0.push_zone_card(MONSTER_ZONE_IDX, under)

	assert_bool(_enter(s, card, MONSTER_ZONE_IDX, Source.EVOLUTION)).is_false()

	assert_array(p0.zones[MONSTER_ZONE_IDX]).contains_exactly([under])
	assert_array(p0.main_deck).contains_exactly([card])
	# No <Enter> or "when played" — only the crush of the base card (11.3).
	assert_array(await _resolve(s)).contains_exactly(["leave:BASE:%d" % MONSTER_ZONE_IDX])
	_teardown(s)
