extends GdUnitTestSuite

## InvasionResolver: cost payment, step movement with crush, victory, and the
## discard-only invade at a defended zone 8.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_invade_2_moves_two_zones_and_pays_cost() -> void:
	var state := States.make_state({"p0": {
		"hand": [Cards.battle(1, 5000, "COST", [], 2)],
		"monster_zone": 1,
	}})
	var session := States.make_session(state)

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	var player: PlayerState = state.players[0]
	assert_int(player.monster_zone).is_equal(3)
	assert_int(player.invasion_zones_crossed).is_equal(2)
	assert_bool(player.has_invaded_this_turn).is_true()
	assert_int(player.hand.size()).is_equal(0)
	assert_int(player.discard_pile.size()).is_equal(1)
	assert_str(str(player.last_invasion_card.get("id"))).is_equal("COST")


func test_invade_crushes_own_battle_card_in_path() -> void:
	var state := States.make_state({"p0": {
		"hand": [Cards.battle(1, 5000, "COST", [], 1)],
		"monster_zone": 1,
		"zone_cards": {1: Cards.battle(1, 5000, "VICTIM")},  # zone 2
	}})
	var session := States.make_session(state)
	var crushed: Array = []
	session["events"].battle_card_crushed.connect(func(_pid: int, zone_idx: int, card: Dictionary) -> void:
		crushed.append([zone_idx, card.get("id", "")]))

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(crushed.size()).is_equal(1)
	assert_int(crushed[0][0]).is_equal(1)
	assert_str(str(crushed[0][1])).is_equal("VICTIM")
	assert_bool(state.players[0].zone_has_cards(1)).is_false()
	# Cost + crushed card both in discard.
	assert_int(state.players[0].discard_pile.size()).is_equal(2)


func test_invasion_victory_past_undefended_zone_8() -> void:
	var state := States.make_state({"p0": {
		"hand": [Cards.battle(1, 5000, "COST", [], 1)],
		"monster_zone": 8,
	}})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(winner_id: int, reason: String) -> void: game_overs.append([winner_id, reason]))

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(9)
	assert_int(game_overs.size()).is_equal(1)
	assert_int(game_overs[0][0]).is_equal(0)
	assert_str(str(game_overs[0][1])).is_equal("STR_LOG_REASON_INVASION_VICTORY")


func test_discard_only_invade_at_defended_zone_8() -> void:
	# Defender in opponent zone 8 blocks movement; the invade is cost-only.
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1, 5000, "COST", [], 1)], "monster_zone": 8},
		"p1": {"zone_cards": {7: Cards.battle(1, 5000, "DEF")}},
	})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(_w: int, _r: String) -> void: game_overs.append(1))

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(8)
	assert_int(state.players[0].invasion_zones_crossed).is_equal(0)
	assert_bool(state.players[0].has_invaded_this_turn).is_true()
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_array(game_overs).is_empty()


func test_invade_stops_at_defended_zone_8_mid_movement() -> void:
	# Invade 2 from zone 7: one step to 8, then blocked.
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1, 5000, "COST", [], 2)], "monster_zone": 7},
		"p1": {"zone_cards": {7: Cards.battle(1, 5000, "DEF")}},
	})
	var session := States.make_session(state)

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(8)
	assert_int(state.players[0].invasion_zones_crossed).is_equal(1)
