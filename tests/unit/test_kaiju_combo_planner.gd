extends GdUnitTestSuite

## KAIJU planner combo awareness: the active combo's forced action leads the
## candidate list, its reserved pieces stay out of the generic pools, and the
## evaluator's combo_progress feature rewards holding the line together.
## Uses a stub combo — BotComboShin's own detection has its own coverage.

const GODZILLA_R1 := "ESD01-001"
const VANILLA_BATTLE := "ESD01-008"


class StubCombo extends BotCombo:
	var plan: Dictionary = {}
	var forced: Array = []

	func _init() -> void:
		combo_name = "stub"
		enabled = true

	func check(_player: PlayerState, _opponent: PlayerState, _bot) -> Dictionary:
		return plan

	func get_execution_action(_plan: Dictionary, _valid_actions: Array,
			_player: PlayerState, _opponent: PlayerState, _bot) -> Array:
		return forced


func _build_state() -> GameState:
	var monster: Dictionary = CardData.get_card_by_id(GODZILLA_R1)
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	var state := GameState.new()
	state.turn_number = 3
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_sub_phase = 1
	for pid in range(2):
		var p := state.players[pid]
		p.current_monster = monster.duplicate(true)
		p.monster_zone = 3
		p.rage = 1
		for i in range(3):
			p.hand.append(battle.duplicate(true))
			p.main_deck.append(battle.duplicate(true))
		p.hand.append(monster.duplicate(true)) # hand index 3: rage fodder
	return state


func _rollout_with_stub(plan: Dictionary, forced: Array) -> KaijuRollout:
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	var stub := StubCombo.new()
	stub.plan = plan
	stub.forced = forced
	rollout.policy._combos = [stub] as Array[BotCombo]
	return rollout


func test_combo_execution_action_is_first_candidate() -> void:
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.config = BotConfig.kaiju()
	bot.game_state = _build_state()
	var planner := KaijuPlanner.new(bot)
	var rollout := _rollout_with_stub(
			{"combo_name": "stub", "state": "full", "viability": 120,
				"reserved_indices": [0], "boosted_indices": [], "monster_play_rules": {}},
			[CardEnums.ActionType.GAIN_RAGE, {"hand_index": 3}])

	var candidates := planner._enumerate_candidates(rollout, 1, bot.config)

	assert_bool(candidates.is_empty()).is_false()
	assert_int(candidates[0]["action"]).is_equal(CardEnums.ActionType.GAIN_RAGE)
	assert_that(candidates[0]["params"]).is_equal({"hand_index": 3})
	# The generic GAIN_RAGE candidate picks the same monster card — deduped.
	var rage_count: int = 0
	for cand in candidates:
		if cand["action"] == CardEnums.ActionType.GAIN_RAGE:
			rage_count += 1
	assert_int(rage_count).is_equal(1)
	rollout.release()


func test_reserved_pieces_excluded_from_generic_pools() -> void:
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.config = BotConfig.kaiju()
	bot.game_state = _build_state()
	var planner := KaijuPlanner.new(bot)
	var rollout := _rollout_with_stub(
			{"combo_name": "stub", "state": "full", "viability": 120,
				"reserved_indices": [0], "boosted_indices": [], "monster_play_rules": {}},
			[])

	var candidates := planner._enumerate_candidates(rollout, 1, bot.config)

	for cand in candidates:
		if cand["action"] == CardEnums.ActionType.PLAY_BATTLE \
				or cand["action"] == CardEnums.ActionType.INVADE:
			assert_int(cand["params"].get("hand_index", -1)).is_not_equal(0)
	rollout.release()


func test_evaluator_rewards_combo_progress() -> void:
	var config := BotConfig.kaiju()
	var evaluator := KaijuEvaluator.new(config)
	var full_plan := {"combo_name": "stub", "state": "full", "viability": 120,
			"reserved_indices": [0], "boosted_indices": [], "monster_play_rules": {}}

	config.kaiju_eval_weights["mid"]["combo_progress"] = 0.0
	var rollout := _rollout_with_stub(full_plan, [])
	var base: float = evaluator.evaluate(rollout, 1, "mid")

	config.kaiju_eval_weights["mid"]["combo_progress"] = 1.0
	var with_full: float = evaluator.evaluate(rollout, 1, "mid")
	assert_float(with_full - base).is_equal_approx(120.0, 0.01)

	# Partial state counts a fraction of viability.
	(rollout.policy._combos[0] as StubCombo).plan = {"combo_name": "stub",
			"state": "partial", "viability": 100, "reserved_indices": [0],
			"boosted_indices": [], "monster_play_rules": {}}
	var with_partial: float = evaluator.evaluate(rollout, 1, "mid")
	assert_float(with_partial - base).is_equal_approx(40.0, 0.01)
	rollout.release()
