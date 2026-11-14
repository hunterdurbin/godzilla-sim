extends GdUnitTestSuite

## EnterZone, deck source: an effect plays a battle card the caller already
## took out of the deck. It overloads the zone (or, "play it on top of",
## keeps the stack), fires <Enter> as an effect play and the "when played"
## watchers with played_from_deck = true. A refused card goes back on the
## deck bottom.

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


func test_a_deck_play_overloads_and_fires_enter_and_played_from_deck() -> void:
	var s := _setup({"zone_cards": {ZONE: Probe.card("OLD")}})
	var card := Probe.card("NEW")
	var p0: PlayerState = s["state"].players[0]

	assert_bool(_enter(s, card, ZONE, Source.DECK)).is_true()
	assert_array(s["probe"].seen).is_empty()

	assert_array(p0.zones[ZONE]).contains_exactly([card])
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
			"leave:OLD:%d" % ZONE, "enter:NEW:effect=true:evo=false",
			"played@WATCH:%d:deck=true" % ZONE])
	_teardown(s)


func test_play_it_on_top_of_keeps_the_stack() -> void:
	var under := Probe.card("UNDER")
	var s := _setup({"zone_cards": {ZONE: under}})
	var card := Probe.card("TOP")
	var p0: PlayerState = s["state"].players[0]

	assert_bool(_enter(s, card, ZONE, Source.DECK, true)).is_true()

	assert_array(p0.zones[ZONE]).contains_exactly([card, under])
	assert_array(await _resolve(s)).not_contains(["leave:UNDER:%d" % ZONE])
	_teardown(s)


func test_a_refused_deck_card_goes_back_on_the_deck_bottom() -> void:
	var s := _setup({"main_deck": [Probe.card("D1")]})
	var card := Probe.card("NEW")
	var p0: PlayerState = s["state"].players[0]

	assert_bool(_enter(s, card, MONSTER_ZONE_IDX, Source.DECK)).is_false()

	assert_dict(p0.main_deck.back()).is_equal(card)
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	assert_array(await _resolve(s)).is_empty()
	_teardown(s)
