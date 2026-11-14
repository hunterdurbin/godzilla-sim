extends GdUnitTestSuite

## MonsterMover, the monster-movement module (GLOSSARY: Advance): the sole
## writer of monster_zone. An advance runs Crush per step and collects the
## "monster advances" entries; only an advance from an invasion (5.13)
## collects <When invading> (12.3) and can move past zone 8 for victory
## through invasion (5.13.1.1.2). Retreat crushes per step without advance
## triggers; teleport crushes only its destination.

const States := preload("res://tests/fixtures/states.gd")
const Probe := preload("res://tests/fixtures/effects/monster_movement_probe.gd")


## p0's probe monster in `zone`; opts merge into p0's options.
func _setup(zone: int, p0: Dictionary = {}, p1: Dictionary = {}) -> Dictionary:
	var p0_opts: Dictionary = {"monster_zone": zone, "current_monster": Probe.monster()}
	p0_opts.merge(p0, true)
	var state := States.make_state({"p0": p0_opts, "p1": p1})
	var s := States.make_session(state)
	s["state"] = state
	s["probe"] = Probe.register(s["effect_handler"])
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


func _mover(s: Dictionary) -> MonsterMover:
	var handler: EffectHandler = s["effect_handler"]
	return handler.monster_mover


## Submit `entries`, resolve the check timing and return what the probe saw.
func _resolve(s: Dictionary, entries: Array = []) -> Array:
	var handler: EffectHandler = s["effect_handler"]
	handler.check_timing.submit(entries)
	await handler.check_timing.resolve()
	return s["probe"].seen


func _p0(s: Dictionary) -> PlayerState:
	return s["state"].players[0]


# --- advance ---


func test_an_advance_from_an_invasion_collects_when_invading_and_advance_per_step() -> void:
	var s := _setup(2)
	var entries: Array = []

	var victory := _mover(s).advance(0, 2, true, entries)

	assert_bool(victory).is_false()
	assert_int(_p0(s).monster_zone).is_equal(4)
	assert_array(await _resolve(s, entries)).contains_exactly_in_any_order([
			"invading:MON:2>3", "advance:MON:2>3",
			"invading:MON:3>4", "advance:MON:3>4"])
	_teardown(s)


func test_an_advance_not_from_an_invasion_collects_no_when_invading() -> void:
	var s := _setup(2)
	var entries: Array = []

	_mover(s).advance(0, 2, false, entries)

	assert_int(_p0(s).monster_zone).is_equal(4)
	assert_array(await _resolve(s, entries)).contains_exactly_in_any_order([
			"advance:MON:2>3", "advance:MON:3>4"])
	_teardown(s)


func test_an_advance_crushes_the_battle_card_in_each_zone_it_crosses() -> void:
	var crossed := Probe.card("CROSSED")
	var s := _setup(1, {"zone_cards": {1: crossed}})  # zone 2
	var entries: Array = []

	_mover(s).advance(0, 3, false, entries)

	assert_int(_p0(s).monster_zone).is_equal(4)
	assert_bool(_p0(s).zone_has_cards(1)).is_false()
	assert_array(_p0(s).discard_pile).contains([crossed])
	assert_array(await _resolve(s, entries)).contains(["leave:CROSSED:1"])
	_teardown(s)


func test_an_invasion_past_an_undefended_zone_8_is_victory() -> void:
	var s := _setup(8)
	var entries: Array = []

	var victory := _mover(s).advance(0, 2, true, entries)

	assert_bool(victory).is_true()
	assert_int(_p0(s).monster_zone).is_equal(9)
	assert_array(await _resolve(s, entries)).contains_exactly(["invading:MON:8>9"])
	_teardown(s)


func test_an_invasion_stops_at_zone_8_when_the_opponent_defends_it() -> void:
	var s := _setup(8, {}, {"zone_cards": {7: Probe.card("DEFENDER")}})
	var entries: Array = []

	var victory := _mover(s).advance(0, 1, true, entries)

	assert_bool(victory).is_false()
	assert_int(_p0(s).monster_zone).is_equal(8)
	assert_array(entries).is_empty()
	_teardown(s)


func test_an_advance_not_from_an_invasion_stops_at_zone_8() -> void:
	var s := _setup(7)
	var entries: Array = []

	var victory := _mover(s).advance(0, 3, false, entries)

	assert_bool(victory).is_false()
	assert_int(_p0(s).monster_zone).is_equal(8)
	assert_array(await _resolve(s, entries)).contains_exactly(["advance:MON:7>8"])
	_teardown(s)


func test_advance_to_zone_stops_at_the_target() -> void:
	var s := _setup(3)
	var entries: Array = []

	_mover(s).advance_to_zone(0, 5, entries)

	assert_int(_p0(s).monster_zone).is_equal(5)
	assert_array(await _resolve(s, entries)).contains_exactly_in_any_order([
			"advance:MON:3>4", "advance:MON:4>5"])
	_teardown(s)


func test_an_advance_emits_monster_advanced_per_step() -> void:
	var s := _setup(2)
	var moves := _record_advanced(s)

	_mover(s).advance(0, 2, false, [])

	assert_array(moves).is_equal([[0, 2, 3], [0, 3, 4]])
	_teardown(s)


func test_an_effect_advance_emits_monster_advanced_and_monster_changed_per_step() -> void:
	var s := _setup(2)
	var handler: EffectHandler = s["effect_handler"]
	var moves := _record_advanced(s)
	var changes := _count_changed(_p0(s))

	handler.advance_monster_to_zone(0, 4)

	assert_int(_p0(s).monster_zone).is_equal(4)
	assert_array(moves).is_equal([[0, 2, 3], [0, 3, 4]])
	assert_int(changes[0]).is_equal(2)
	_teardown(s)


func test_an_invasion_emits_monster_changed_only_on_the_victory_step() -> void:
	var s := _setup(7)
	var changes := _count_changed(_p0(s))

	assert_bool(_mover(s).advance(0, 1, true, [])).is_false()
	assert_int(changes[0]).is_equal(0)

	assert_bool(_mover(s).advance(0, 1, true, [])).is_true()
	assert_int(changes[0]).is_equal(1)
	_teardown(s)


func _record_advanced(s: Dictionary) -> Array:
	var events: GameEvents = s["events"]
	var moves: Array = []
	events.monster_advanced.connect(func(pid: int, from: int, to: int) -> void:
		moves.append([pid, from, to]))
	return moves


## One-slot counter (an Array, so the lambda can mutate it).
func _count_changed(player: PlayerState) -> Array:
	var count: Array = [0]
	player.monster_changed.connect(func() -> void: count[0] += 1)
	return count


# --- retreat ---


func test_a_retreat_crushes_per_step_without_advance_triggers() -> void:
	var crossed := Probe.card("CROSSED")
	var s := _setup(5, {"zone_cards": {3: crossed}})  # zone 4
	var entries: Array = []

	_mover(s).retreat_to_zone(0, 2, entries)

	assert_int(_p0(s).monster_zone).is_equal(2)
	assert_bool(_p0(s).zone_has_cards(3)).is_false()
	assert_array(await _resolve(s, entries)).contains_exactly(["leave:CROSSED:3"])
	_teardown(s)


func test_an_effect_retreat_emits_monster_advanced_and_monster_changed_per_step() -> void:
	# monster_advanced reports every move, downward ones included (as the
	# counter retreat's teleport does).
	var s := _setup(5)
	var handler: EffectHandler = s["effect_handler"]
	var moves := _record_advanced(s)
	var changes := _count_changed(_p0(s))

	handler.retreat_monster_to_zone(0, 3)

	assert_int(_p0(s).monster_zone).is_equal(3)
	assert_array(moves).is_equal([[0, 5, 4], [0, 4, 3]])
	assert_int(changes[0]).is_equal(2)
	_teardown(s)


# --- teleport ---


func test_a_teleport_crushes_only_its_destination() -> void:
	var crossed := Probe.card("CROSSED")
	var landed := Probe.card("LANDED")
	var s := _setup(3, {"zone_cards": {4: crossed, 7: landed}})  # zones 5 and 8

	_mover(s).teleport(0, 8)

	assert_int(_p0(s).monster_zone).is_equal(8)
	assert_array(_p0(s).zones[4]).contains_exactly([crossed])
	assert_bool(_p0(s).zone_has_cards(7)).is_false()
	assert_array(await _resolve(s)).contains_exactly(["leave:LANDED:7"])
	_teardown(s)


func test_a_counter_retreat_moves_zone_8_back_to_zone_3_and_crushes_it() -> void:
	var landed := Probe.card("LANDED")
	var s := _setup(8, {"zone_cards": {2: landed}})  # zone 3
	var moves := _record_advanced(s)

	assert_bool(_mover(s).counter_retreat(0)).is_true()

	assert_int(_p0(s).monster_zone).is_equal(3)
	assert_array(moves).is_equal([[0, 8, 3]])
	assert_bool(_p0(s).zone_has_cards(2)).is_false()
	assert_array(await _resolve(s)).contains_exactly(["leave:LANDED:2"])
	_teardown(s)


func test_a_counter_retreat_leaves_zones_below_6_in_place() -> void:
	var s := _setup(5)

	assert_bool(_mover(s).counter_retreat(0)).is_false()

	assert_int(_p0(s).monster_zone).is_equal(5)
	_teardown(s)
