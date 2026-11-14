extends GdUnitTestSuite

## EnterZone, token source: an effect puts a token into existence in a zone.
## A battle token is a play: it overloads the zone, fires its <Enter> as an
## effect play and the "when played" watchers (not from the deck).

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


func test_a_battle_token_overloads_and_counts_as_a_play() -> void:
	var s := _setup({"zone_cards": {ZONE: Probe.card("OLD")}})
	var token := Probe.card("TOKEN")

	assert_bool(_enter(s, token, ZONE, Source.TOKEN)).is_true()

	assert_dict(s["state"].players[0].get_zone_top_card(ZONE)).is_equal(token)
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
			"leave:OLD:%d" % ZONE, "enter:TOKEN:effect=true:evo=false",
			"played@WATCH:%d:deck=false" % ZONE])
	_teardown(s)


func test_a_non_battle_token_does_not_fire_the_played_watchers() -> void:
	var s := _setup()
	var token := Probe.card("TOKEN")
	token["card_type"] = CardEnums.CardType.STRATEGY

	assert_bool(_enter(s, token, ZONE, Source.TOKEN)).is_true()

	assert_array(await _resolve(s)).contains_exactly(["enter:TOKEN:effect=true:evo=false"])
	_teardown(s)


func test_a_token_is_refused_in_the_monster_zone() -> void:
	var s := _setup()
	assert_bool(_enter(s, Probe.card("TOKEN"), MONSTER_ZONE_IDX, Source.TOKEN)).is_false()
	assert_bool(s["state"].players[0].zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	_teardown(s)


func test_create_token_in_zone_places_a_fresh_instance_through_the_operation() -> void:
	var s := _setup()
	var handler: EffectHandler = s["effect_handler"]
	var p0: PlayerState = s["state"].players[0]

	assert_bool(handler.create_token_in_zone(p0, "EBP02-T03", MONSTER_ZONE_IDX)).is_false()
	assert_bool(handler.create_token_in_zone(p0, "EBP02-T03", ZONE)).is_true()

	# The refused attempt took no instance serial.
	assert_str(p0.get_zone_top_card(ZONE).get("id")).is_equal("EBP02-T03_tok_1")
	assert_array(await _resolve(s)).contains(["played@WATCH:%d:deck=false" % ZONE])
	_teardown(s)
