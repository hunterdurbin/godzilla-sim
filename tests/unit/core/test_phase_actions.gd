extends GdUnitTestSuite

## PhaseActions: start-phase draw / strategy discard / reset, end-phase
## advance + crush + hand refill, and main-phase plays through execute().

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_start_phase_draw_count_follows_opponent_monster_rank() -> void:
	var state := States.make_state({
		"p0": {"main_deck": [Cards.battle(1), Cards.battle(1), Cards.battle(1)]},
		"p1": {"current_monster": Cards.monster(2, 7000)},
	})
	var session := States.make_session(state)
	session["action_handler"].execute_start_phase_draw(state)
	assert_int(state.players[0].hand.size()).is_equal(2)


func test_start_phase_discard_clears_old_strategies_only() -> void:
	var state := States.make_state({
		"turn_number": 3,
		"p0": {"strategy_zones": [Cards.strategy(1, "OLD"), Cards.strategy(1, "NEW")]},
	})
	state.players[0].strategy_zone_turn_placed = [2, 3]  # OLD placed last turn, NEW this turn
	var session := States.make_session(state)

	await session["action_handler"].execute_start_phase_discard(state)

	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_true()
	assert_str(str(state.players[0].strategy_zones[1].get("id"))).is_equal("NEW")
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_start_phase_reset_zeroes_rage_and_flags() -> void:
	var state := States.make_state({"p0": {
		"rage": 3,
		"has_invaded_this_turn": true,
		"has_played_monster_this_turn": true,
	}})
	state.players[0].invasion_zones_crossed = 2
	var session := States.make_session(state)

	await session["action_handler"].execute_start_phase_reset(state)

	var player: PlayerState = state.players[0]
	assert_int(player.rage).is_equal(0)
	assert_bool(player.has_invaded_this_turn).is_false()
	assert_bool(player.has_played_monster_this_turn).is_false()
	assert_int(player.invasion_zones_crossed).is_equal(0)


func test_end_phase_advance_moves_one_zone_and_crushes() -> void:
	var state := States.make_state({"p0": {
		"monster_zone": 4,
		"zone_cards": {4: Cards.battle(1, 5000, "IN-PATH")},  # zone 5
	}})
	var session := States.make_session(state)

	await session["action_handler"].execute_end_phase_advance(state)

	assert_int(state.players[0].monster_zone).is_equal(5)
	assert_bool(state.players[0].zone_has_cards(4)).is_false()


func test_end_phase_advance_stops_at_zone_8() -> void:
	var state := States.make_state({"p0": {"monster_zone": 8}})
	var session := States.make_session(state)
	await session["action_handler"].execute_end_phase_advance(state)
	assert_int(state.players[0].monster_zone).is_equal(8)


func test_end_phase_draw_refills_to_five() -> void:
	var deck: Array = []
	for i in range(8):
		deck.append(Cards.battle(1, 5000, "D%d" % i))
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)], "main_deck": deck}})
	var session := States.make_session(state)

	session["action_handler"].execute_end_phase_draw(state)

	assert_int(state.players[0].hand.size()).is_equal(5)


func test_end_phase_burst_discard_restores_pre_burst_monster() -> void:
	var pre_burst := Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA], "PRE")
	var burst := Cards.monster(3, 9000, [CardEnums.CardTrait.GODZILLA], "BURST")
	var state := States.make_state({"p0": {"current_monster": burst}})
	state.players[0].burst_monster = burst
	state.players[0].pre_burst_monster = pre_burst
	state.players[0].monster_stack = [pre_burst]
	var session := States.make_session(state)

	await session["action_handler"].execute_end_phase_burst_discard(state)

	var player: PlayerState = state.players[0]
	assert_str(str(player.current_monster.get("id"))).is_equal("PRE")
	assert_bool(player.burst_monster.is_empty()).is_true()
	assert_int(player.monster_stack.size()).is_equal(0)
	assert_str(str(player.discard_pile[0].get("id"))).is_equal("BURST")


func test_execute_play_battle_card_places_in_zone() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1, 5000, "PLAYED")]}})
	var session := States.make_session(state)
	var played: Array = []
	session["events"].battle_card_played.connect(func(_pid: int, card: Dictionary, zone_idx: int) -> void:
		played.append([card.get("id", ""), zone_idx]))

	await session["action_handler"].execute(CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 3}, state)

	assert_str(str(state.players[0].get_zone_top_card(3).get("id"))).is_equal("PLAYED")
	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(played.size()).is_equal(1)


func test_execute_gain_rage_discards_and_increments() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.monster()]}})
	var session := States.make_session(state)

	await session["action_handler"].execute(CardEnums.ActionType.GAIN_RAGE, {"hand_index": 0}, state)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(0)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)


func test_execute_play_monster_same_rank() -> void:
	var new_monster := Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "NEW-M")
	var state := States.make_state({"p0": {"hand": [new_monster]}})
	var session := States.make_session(state)

	await session["action_handler"].execute(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": 0}, state)

	var player: PlayerState = state.players[0]
	assert_str(str(player.current_monster.get("id"))).is_equal("NEW-M")
	assert_bool(player.has_played_monster_this_turn).is_true()
	assert_int(player.rage).is_equal(1)
	assert_int(player.monster_stack.size()).is_equal(1)
	assert_bool(player.burst_monster.is_empty()).is_true()
