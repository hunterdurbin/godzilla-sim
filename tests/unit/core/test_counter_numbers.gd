extends GdUnitTestSuite

## RulesEngine.counter_numbers(q, counterer, defender): the counter numbers
## (5.15) for any counterer, with engagement restriction, counter immunity and
## counter prevention applied — and the bot's CP gap, which reads them
## (hunterdurbin/godzilla-sim-issue-tracker#32).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _queries(state: GameState) -> EffectQueries:
	var handler: EffectHandler = States.make_session(state)["effect_handler"]
	return handler.queries


## P1's turn: P1 counters P0. P0 holds EBP01-028 (strategy, <Opponent's
## Turn>: battle cards of rank 3 or lower can't engage in the counter phase).
func _restricted_state(phase: CardEnums.GamePhase = CardEnums.GamePhase.MAIN) -> GameState:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": Cards.monster(1, 5000), "strategy_zones": [Real.instance("EBP01-028")]},
		"p1": {"zone_cards": {2: Cards.battle(2, 6000, "LOW"), 3: Cards.battle(5, 4000, "HIGH")}},
	})
	state.current_phase = phase
	return state


func test_counter_numbers_without_effects_for_either_counterer() -> void:
	var state := States.make_state({
		"p0": {"current_monster": Cards.monster(1, 7000), "zone_cards": {2: Cards.battle(1, 6000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "rage": 2,
			"zone_cards": {3: Cards.battle(1, 9000, "B")}},
	})
	var q := _queries(state)
	var p0_counters := RulesEngine.counter_numbers(q, state.players[0], state.players[1])
	assert_int(p0_counters["total_cp"]).is_equal(6000)
	assert_int(p0_counters["threat"]).is_equal(15000)
	assert_int(p0_counters["rage_threat"]).is_equal(10000)
	# Not the current player: the numbers are the counterer's, not the turn's.
	var p1_counters := RulesEngine.counter_numbers(q, state.players[1], state.players[0])
	assert_int(p1_counters["total_cp"]).is_equal(9000)
	assert_int(p1_counters["threat"]).is_equal(7000)
	assert_bool(p1_counters["prevented"]).is_false()
	assert_int(p1_counters["immunity_threshold"]).is_equal(0)


func test_compute_counter_numbers_is_the_current_players_counter_numbers() -> void:
	var state := _restricted_state(CardEnums.GamePhase.COUNTER)
	var rules := States.make_rules(state)
	var expected := RulesEngine.counter_numbers(rules.queries, state.players[1], state.players[0])
	assert_dict(rules.compute_counter_numbers(state)).is_equal(expected)


func test_counter_numbers_subtract_engagement_restricted_cp(phase: CardEnums.GamePhase,
		test_parameters := [[CardEnums.GamePhase.MAIN], [CardEnums.GamePhase.COUNTER]]) -> void:
	# The numbers are the coming counter phase's, so the restriction applies
	# while the counterer plans its main phase too (#32).
	var state := _restricted_state(phase)
	var q := _queries(state)
	var numbers := RulesEngine.counter_numbers(q, state.players[1], state.players[0])
	# The rank-2 card (6000) can't engage; only the rank-5 card counts.
	assert_int(numbers["total_cp"]).is_equal(4000)
	# The live-phase query keeps its counter-phase gate for other CP readers.
	var expected_live: int = 3 if phase == CardEnums.GamePhase.COUNTER else -1
	assert_int(q.get_engagement_restriction(0)).is_equal(expected_live)


func test_turn_gated_restriction_spares_the_non_current_player() -> void:
	# P0's turn: EBP01-028 is P0's <Opponent's Turn> card, so P1 (not
	# countering this turn) keeps its full CP on the board label.
	var state := _restricted_state()
	state.current_player_id = 0
	var numbers := RulesEngine.counter_numbers(_queries(state), state.players[1], state.players[0])
	assert_int(numbers["total_cp"]).is_equal(10000)


func test_counter_numbers_report_immunity_threshold() -> void:
	# EBP01-038: <Opponent's Turn> + Awakening6 → immune at CP <= 50000.
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": Real.instance("EBP01-038"), "monster_zone": 6},
	})
	var numbers := RulesEngine.counter_numbers(_queries(state), state.players[1], state.players[0])
	assert_int(numbers["immunity_threshold"]).is_equal(50000)
	assert_bool(numbers["prevented"]).is_false()


func test_counter_numbers_report_prevention() -> void:
	# EBP04-031: the counter can't happen while the counterer has <= 1 battle card.
	var state := States.make_state({
		"p0": {"current_monster": Real.instance("EBP04-031")},
		"p1": {"monster_zone": 2, "zone_cards": {0: Cards.battle(2, 90000, "WALL")}},
	})
	var numbers := RulesEngine.counter_numbers(_queries(state), state.players[1], state.players[0])
	assert_int(numbers["total_cp"]).is_equal(90000)
	assert_bool(numbers["prevented"]).is_true()


# --- Bot CP gap (#32) ---


func _bot(state: GameState) -> BotPlayer:
	var session := States.make_session(state)
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.game_state = state
	bot.effect_handler = session["effect_handler"]
	bot.rules_engine = session["rules"]
	return bot


func test_bot_cp_gap_subtracts_engagement_restricted_cp() -> void:
	var bot := _bot(_restricted_state())
	# Threat 5000 vs 4000 engaging CP (the 6000 card is restricted).
	assert_int(bot.get_cp_gap()).is_equal(1000)
	assert_bool(bot.can_counter_opponent()).is_false()


func test_bot_cannot_counter_a_prevented_counter() -> void:
	var state := States.make_state({
		"p0": {"current_monster": Real.instance("EBP04-031")},
		"p1": {"monster_zone": 2, "zone_cards": {0: Cards.battle(2, 90000, "WALL")}},
	})
	var bot := _bot(state)
	assert_bool(bot.get_cp_gap() <= 0).is_true()
	assert_bool(bot.can_counter_opponent()).is_false()
