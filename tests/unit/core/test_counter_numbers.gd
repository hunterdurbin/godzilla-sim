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


func test_counter_numbers_read_turn_gates_as_of_the_counterers_turn() -> void:
	# P0's main phase. EBP01-028 is P0's <Opponent's Turn> card: it restricts
	# P1's counter next turn, so P1's numbers already leave the 6000 out.
	var state := _restricted_state()
	state.current_player_id = 0
	var q := _queries(state)
	var numbers := RulesEngine.counter_numbers(q, state.players[1], state.players[0])
	assert_int(numbers["total_cp"]).is_equal(4000)
	# The view is scoped: live queries and the state are untouched afterwards.
	assert_int(q.get_engagement_restriction(0)).is_equal(-1)
	assert_int(state.current_player_id).is_equal(0)
	assert_int(state.current_phase).is_equal(CardEnums.GamePhase.MAIN)


func test_fest_godzilla_restriction_from_its_owners_main_phase() -> void:
	# EBP01-014 (<Opponent's Turn> + Awakening4 + 2 own battle cards):
	# battle cards of rank 5 or lower can't engage. P0's main phase; P1's
	# coming counter already loses its rank-5 card.
	var state := States.make_state({
		"p0": {
			"current_monster": Real.instance("EBP01-014"),
			"monster_zone": 4,
			"zone_cards": {0: Cards.battle(2, 3000, "B-0"), 1: Cards.battle(2, 3000, "B-1")},
		},
		"p1": {"zone_cards": {2: Cards.battle(5, 6000, "R5"), 3: Cards.battle(7, 4000, "R7")}},
	})
	var numbers := RulesEngine.counter_numbers(_queries(state), state.players[1], state.players[0])
	assert_int(numbers["total_cp"]).is_equal(4000)


func test_counter_views_nest_and_restore() -> void:
	# P0's main phase; P0 holds EBP01-028 (<Opponent's Turn>, rank <= 3).
	var state := _restricted_state()
	state.current_player_id = 0
	var q := _queries(state)
	var seen: Array = q.in_counter_view(1, func() -> Array:
		var outer: int = q.get_engagement_restriction(0)
		var inner: int = q.in_counter_view(0, func() -> int: return q.get_engagement_restriction(0))
		return [outer, inner, q.get_engagement_restriction(0)])
	# P1's counter: restricted; P0's own counter: not; back in P1's view: restricted.
	assert_array(seen).contains_exactly([3, -1, 3])
	assert_int(q.get_engagement_restriction(0)).is_equal(-1)


func test_counter_numbers_report_immunity_threshold() -> void:
	# EBP01-038: <Opponent's Turn> + Awakening6 → immune at CP <= 50000.
	# Evaluated on P0's own turn: the gate reads P1's coming counter.
	var state := States.make_state({
		"current_player_id": 0,
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
	assert_bool(numbers["lands"]).is_false()


func test_projected_cp_counts_toward_prevention() -> void:
	# EBP04-014-style CP-conditional prevention reads total_cp; projected CP
	# (KAIJU's opponent growth) is part of it.
	var state := States.make_state({
		"p1": {"current_monster": Cards.monster(1, 5000), "zone_cards": {2: Cards.battle(1, 3000)}},
	})
	var numbers := RulesEngine.counter_numbers(_queries(state), state.players[0], state.players[1], 4000)
	assert_int(numbers["total_cp"]).is_equal(4000)
	assert_int(numbers["gap"]).is_equal(1000)
	assert_bool(numbers["lands"]).is_false()


# --- Board labels and badges (ModifierBreakdown.counter_labels) ---


func test_label_mods_show_each_players_coming_counter() -> void:
	# P1's main phase; P0 holds EBP01-028. P1's CP label drops the restricted
	# 6000 already; P0's labels are unaffected.
	var state := _restricted_state()
	var q := _queries(state)
	var mods := ModifierBreakdown.counter_labels(q, state.players)
	assert_int(mods["cp"][1]).is_equal(-6000)
	assert_int(mods["cp"][0]).is_equal(0)
	assert_int(mods["threat"][0]).is_equal(0)
	# Badges come from the same view, so they add up to the label (the
	# restricted card's printed CP is the only term outside them).
	var badge_sum: int = int(mods["monster_cp"][1])
	for v in mods["zone_cp"][1]:
		badge_sum += int(v)
	for v in mods["strategy_cp"][1]:
		badge_sum += int(v)
	assert_int(badge_sum - 6000).is_equal(mods["cp"][1])


# --- Shin threat surplus ---


func test_shin_threat_surplus_sees_the_restriction_on_the_opponents_counter() -> void:
	# The bot (P1) plans its own turn; its EBP01-028 (<Opponent's Turn>)
	# will restrict P0's counter next turn. Surplus = 5000 - 4000.
	var state := States.make_state({
		"current_player_id": 1,
		"p1": {"current_monster": Cards.monster(1, 5000), "strategy_zones": [Real.instance("EBP01-028")]},
		"p0": {"zone_cards": {2: Cards.battle(2, 6000, "LOW"), 3: Cards.battle(5, 4000, "HIGH")}},
	})
	var shin := BotComboShin.new()
	assert_int(shin._get_threat_surplus(state.players[1], state.players[0], _queries(state))).is_equal(1000)


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
