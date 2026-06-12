extends GdUnitTestSuite

## RuleActions: crush rule (11.3) and illegal cards (11.4) at check timings.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_crush_destroys_battle_card_under_monster() -> void:
	var state := States.make_state({"p0": {
		"monster_zone": 3,
		"zone_cards": {2: Cards.battle(1, 5000, "UNDER")},
	}})
	var session := States.make_session(state)

	await session["action_handler"].resolve_check_timing(state)

	assert_bool(state.players[0].zone_has_cards(2)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(state.players[0].cards_destroyed_this_turn.size()).is_equal(1)


func test_crush_checks_both_players_turn_player_first() -> void:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"monster_zone": 2, "zone_cards": {1: Cards.battle(1, 5000, "P0")}},
		"p1": {"monster_zone": 5, "zone_cards": {4: Cards.battle(1, 5000, "P1")}},
	})
	var session := States.make_session(state)
	var crush_order: Array = []
	session["events"].battle_card_crushed.connect(func(pid: int, _z: int, _c: Dictionary) -> void:
		crush_order.append(pid))

	await session["action_handler"].resolve_check_timing(state)

	# Turn player (1) crushes first (11.1.2.1.1).
	assert_array(crush_order).contains_exactly([1, 0])


func test_no_crush_when_zone_clear() -> void:
	var state := States.make_state({"p0": {
		"monster_zone": 3,
		"zone_cards": {4: Cards.battle(1, 5000, "ELSEWHERE")},
	}})
	var session := States.make_session(state)
	await session["action_handler"].resolve_check_timing(state)
	assert_bool(state.players[0].zone_has_cards(4)).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


func test_illegal_strategy_in_zone_discarded() -> void:
	var state := States.make_state({"p0": {
		"zone_cards": {4: Cards.strategy(1, "ILLEGAL")},
	}})
	var session := States.make_session(state)

	await session["action_handler"].resolve_check_timing(state)

	assert_bool(state.players[0].zone_has_cards(4)).is_false()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_illegal_battle_card_in_strategy_zone_discarded() -> void:
	var state := States.make_state({"p0": {
		"strategy_zones": [Cards.battle(1, 5000, "WRONG-SLOT")],
	}})
	var session := States.make_session(state)

	await session["action_handler"].resolve_check_timing(state)

	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
