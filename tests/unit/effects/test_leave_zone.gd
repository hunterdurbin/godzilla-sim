extends GdUnitTestSuite

## LeaveZone.leave: a battle card in a zone goes to an area that is not a
## zone (GLOSSARY: Leave). Whatever the destination, the zone is emptied, the
## cards under the top card go to the discard pile (tokens are banished), and
## the top card's on_leave_play enters standby (10.6.4). A token whose
## destination is not a zone disappears (9.1.4.2).

const States := preload("res://tests/fixtures/states.gd")
const Probe := preload("res://tests/fixtures/effects/enter_zone_probe.gd")

const Destination := LeaveZone.Destination

const ZONE := 5


func _setup() -> Dictionary:
	var state := States.make_state({"p0": {"monster_zone": 4}})
	var s := States.make_session(state)
	s["state"] = state
	s["probe"] = Probe.register(s["effect_handler"])
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


## Put TOP over UNDER in p0's zone ZONE and return [top, under].
func _stack(s: Dictionary, top_traits: Array = []) -> Array:
	var p0: PlayerState = s["state"].players[0]
	var top := Probe.card("TOP")
	top["traits"] = top_traits
	var under := Probe.card("UNDER")
	p0.push_zone_card(ZONE, under)
	p0.push_zone_card(ZONE, top)
	return [top, under]


func _leave(s: Dictionary, destination: LeaveZone.Destination) -> Dictionary:
	var handler: EffectHandler = s["effect_handler"]
	return handler.leave_zone.leave(0, ZONE, destination)


func _resolve(s: Dictionary) -> Array:
	var handler: EffectHandler = s["effect_handler"]
	await handler.check_timing.resolve()
	return s["probe"].seen


func test_leaving_to_the_discard_pile_discards_the_whole_stack() -> void:
	var s := _setup()
	var cards := _stack(s)
	var p0: PlayerState = s["state"].players[0]

	assert_dict(_leave(s, Destination.DISCARD)).is_equal(cards[0])

	assert_bool(p0.zone_has_cards(ZONE)).is_false()
	assert_array(p0.discard_pile).contains_exactly(cards)
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)


func test_leaving_to_the_hand_adds_the_top_card_and_discards_the_rest() -> void:
	var s := _setup()
	var cards := _stack(s)
	var p0: PlayerState = s["state"].players[0]
	var hand_before := p0.hand.size()

	_leave(s, Destination.HAND)

	assert_bool(p0.zone_has_cards(ZONE)).is_false()
	assert_int(p0.hand.size()).is_equal(hand_before + 1)
	assert_dict(p0.hand[-1]).is_equal(cards[0])
	assert_array(p0.discard_pile).contains_exactly([cards[1]])
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)


func test_leaving_to_the_deck_top_puts_the_top_card_on_the_deck() -> void:
	var s := _setup()
	var cards := _stack(s)
	var p0: PlayerState = s["state"].players[0]

	_leave(s, Destination.DECK_TOP)

	assert_bool(p0.zone_has_cards(ZONE)).is_false()
	assert_dict(p0.main_deck[0]).is_equal(cards[0])
	assert_array(p0.discard_pile).contains_exactly([cards[1]])
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)


func test_leaving_to_the_deck_bottom_puts_the_top_card_under_the_deck() -> void:
	var s := _setup()
	var cards := _stack(s)
	var p0: PlayerState = s["state"].players[0]

	_leave(s, Destination.DECK_BOTTOM)

	assert_bool(p0.zone_has_cards(ZONE)).is_false()
	assert_dict(p0.main_deck[-1]).is_equal(cards[0])
	assert_array(p0.discard_pile).contains_exactly([cards[1]])
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)


func test_a_token_leaving_for_the_hand_disappears() -> void:
	var s := _setup()
	var cards := _stack(s, [CardEnums.CardTrait.TOKEN])
	var p0: PlayerState = s["state"].players[0]
	var hand_before := p0.hand.size()

	_leave(s, Destination.HAND)

	assert_int(p0.hand.size()).is_equal(hand_before)
	assert_array(p0.discard_pile).contains_exactly([cards[1]])
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)


func test_leaving_an_empty_zone_does_nothing() -> void:
	var s := _setup()

	assert_dict(_leave(s, Destination.DISCARD)).is_empty()

	assert_array(await _resolve(s)).is_empty()
	_teardown(s)


## hunterdurbin/godzilla-sim-issue-tracker#31: an effect returning a battle card to the deck bottom (ESC01-001) is a
## Leave, so the card's on_leave_play enters standby.
func test_an_effect_returning_a_card_to_the_deck_bottom_fires_leave_play() -> void:
	var s := _setup()
	var cards := _stack(s)
	var p0: PlayerState = s["state"].players[0]
	var handler: EffectHandler = s["effect_handler"]

	handler.move_zone_card_to_deck_bottom(p0, cards[0])

	assert_bool(p0.zone_has_cards(ZONE)).is_false()
	assert_dict(p0.main_deck[-1]).is_equal(cards[0])
	assert_array(await _resolve(s)).contains_exactly(["leave:TOP:%d" % ZONE])
	_teardown(s)
