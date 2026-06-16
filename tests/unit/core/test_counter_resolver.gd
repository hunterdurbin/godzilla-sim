extends GdUnitTestSuite

## CounterResolver: number computation, the four outcome branches, retreat
## zones, rank-up via PlayerInput, and loss when no rank-up exists.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_compute_counter_numbers_without_effects() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 6000), 4: Cards.battle(1, 4000, "B")}},
		"p1": {"current_monster": Cards.monster(1, 5000), "rage": 2},
	})
	var session := States.make_session(state)
	var numbers: Dictionary = session["action_handler"].counter.compute_counter_numbers(state)
	assert_int(numbers["total_cp"]).is_equal(10000)
	assert_int(numbers["threat"]).is_equal(15000)  # 5000 base + 2 rage * 5000
	assert_int(numbers["rage_threat"]).is_equal(10000)
	assert_int(numbers["effect_threat"]).is_equal(0)
	assert_bool(numbers["prevented"]).is_false()


func test_counter_success_retreats_and_ranks_up() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 7,
			"monster_deck": Cards.monster_line(),
		},
	})
	var input := ScriptedPlayerInput.new()
	var session := States.make_session(state, input)
	var outcomes: Array = []
	session["events"].counter_succeeded.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void: outcomes.append("success"))

	await session["action_handler"].resolve_counter(state)

	assert_array(outcomes).contains_exactly(["success"])
	assert_int(state.players[1].monster_zone).is_equal(4)  # 7 -> 4 (5.15.1.1)
	# Ranked up to the rank-2 monster from the deck (default input picks first valid).
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(2)
	assert_int(input.count_calls("choose_rankup")).is_equal(1)
	# Old monster pushed under the new one.
	assert_int(state.players[1].monster_stack.size()).is_equal(1)


func test_counter_failure_no_movement() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 1000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "monster_zone": 7},
	})
	var session := States.make_session(state)
	var outcomes: Array = []
	session["events"].counter_failed.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void: outcomes.append("failed"))

	await session["action_handler"].resolve_counter(state)

	assert_array(outcomes).contains_exactly(["failed"])
	assert_int(state.players[1].monster_zone).is_equal(7)
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(1)


func test_counter_zones_1_to_5_do_not_retreat() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 3,
			"monster_deck": Cards.monster_line(),
		},
	})
	var session := States.make_session(state)
	await session["action_handler"].resolve_counter(state)
	assert_int(state.players[1].monster_zone).is_equal(3)  # zones 1-5 stay put
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(2)  # still ranks up


func test_counter_victory_when_monster_deck_empty() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "monster_deck": []},
	})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(winner_id: int, reason: String) -> void: game_overs.append([winner_id, reason]))

	await session["action_handler"].resolve_counter(state)

	assert_int(game_overs.size()).is_equal(1)
	assert_int(game_overs[0][0]).is_equal(0)
	assert_str(str(game_overs[0][1])).is_equal("STR_LOG_REASON_COUNTER_VICTORY")


func test_counter_victory_when_no_valid_rankup() -> void:
	# Deck has a rank-2 monster but with no shared trait -> no valid target.
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
			"monster_deck": [Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN])],
		},
	})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(winner_id: int, _reason: String) -> void: game_overs.append(winner_id))

	await session["action_handler"].resolve_counter(state)

	assert_array(game_overs).contains_exactly([0])


func test_rankup_uses_scripted_choice() -> void:
	# Two valid rank-2 monsters; the script picks deck index 1.
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 6,
			"monster_deck": [
				Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA], "R2-A"),
				Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA], "R2-B"),
			],
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_rankup": [1]}
	var session := States.make_session(state, input)

	await session["action_handler"].resolve_counter(state)

	assert_str(str(state.players[1].current_monster.get("id"))).is_equal("R2-B")
	assert_int(state.players[1].monster_zone).is_equal(5)  # 6 -> 5


func test_force_counter_targets_specific_player() -> void:
	var state := States.make_state({
		"p0": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 8,
			"monster_deck": Cards.monster_line(),
		},
	})
	var session := States.make_session(state)
	await session["action_handler"].force_counter(state, 0)
	assert_int(state.players[0].monster_zone).is_equal(3)  # 8 -> 3
	assert_int(state.players[0].current_monster.get("rank", 0)).is_equal(2)
