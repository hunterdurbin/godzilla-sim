extends GdUnitTestSuite

## KaijuPlanner — candidate-enumeration determinism and the hash-checked
## plan cache. Uses tiny search budgets; strength is validated by the sim
## harness, not unit tests.

const GODZILLA_R1 := "ESD01-001"
const VANILLA_BATTLE := "ESD01-008"


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
		p.hand.append(monster.duplicate(true))
		for m in CardData.get_monster_deck(CardEnums.CardTrait.GODZILLA):
			if m.get("rank", 0) > 1:
				p.monster_deck.append(m.duplicate(true))
	return state


func _make_bot(state: GameState) -> BotPlayer:
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.config = BotConfig.kaiju()
	bot.config.kaiju_beam_width = 2
	bot.config.kaiju_max_depth = 2
	bot.config.kaiju_node_budget = 24
	bot.config.kaiju_time_budget_ms = 5000
	bot.game_state = state
	return bot


func test_candidate_enumeration_is_deterministic() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	var snap := KaijuRollout.snapshot(bot.game_state)

	seed(777)
	var rollout_a := KaijuRollout.new(snap, 1, bot.config)
	var first := planner._enumerate_candidates(rollout_a, 1, bot.config)
	rollout_a.release()

	seed(777)
	var rollout_b := KaijuRollout.new(snap, 1, bot.config)
	var second := planner._enumerate_candidates(rollout_b, 1, bot.config)
	rollout_b.release()

	assert_that(first).is_equal(second)
	assert_bool(first.is_empty()).is_false()


func test_decide_action_returns_legal_action_and_caches_plan() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	var result: Array = await planner.decide_action([])

	assert_int(result.size()).is_equal(2)
	var valid: Array = [
		CardEnums.ActionType.PLAY_BATTLE, CardEnums.ActionType.PLAY_STRATEGY,
		CardEnums.ActionType.GAIN_RAGE, CardEnums.ActionType.PLAY_MONSTER,
		CardEnums.ActionType.INVADE, CardEnums.ActionType.PASS,
	]
	assert_bool(result[0] in valid).is_true()
	assert_int(planner._plan_turn).is_equal(3)


func test_plan_cache_hit_returns_cached_step_verbatim() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	planner._plan_turn = 3
	planner._plan = [{
		"action": CardEnums.ActionType.GAIN_RAGE, "params": {"hand_index": 3},
		"predicted_hash": StateCodec.compute_state_hash(bot.game_state),
		"card_id": GODZILLA_R1,
	}]

	var result: Array = await planner.decide_action([])
	assert_int(result[0]).is_equal(CardEnums.ActionType.GAIN_RAGE)
	assert_that(result[1]).is_equal({"hand_index": 3})
	assert_bool(planner._plan.is_empty()).is_true()


func test_plan_cache_replans_on_hash_mismatch() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	planner._plan_turn = 3
	planner._plan = [{
		"action": CardEnums.ActionType.INVADE, "params": {"hand_index": 99},
		"predicted_hash": 12345, # wrong on purpose
		"card_id": "",
	}]

	var result: Array = await planner.decide_action([])
	# The bogus cached step must not survive: index 99 is not even a hand slot.
	var params: Dictionary = result[1]
	assert_bool(params.get("hand_index", -1) == 99).is_false()


func test_plan_cache_replans_when_hand_card_changed() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	planner._plan_turn = 3
	planner._plan = [{
		"action": CardEnums.ActionType.PLAY_BATTLE, "params": {"hand_index": 0, "zone_index": 0},
		"predicted_hash": StateCodec.compute_state_hash(bot.game_state),
		"card_id": "SOME-OTHER-CARD", # live hand[0] is the vanilla battle card
	}]

	var result: Array = await planner.decide_action([])
	var step_matches: bool = result[0] == CardEnums.ActionType.PLAY_BATTLE \
			and result[1].get("hand_index", -1) == 0 \
			and result[1].get("zone_index", -1) == 0
	# Either a different action or the same slot re-derived by a real search —
	# but never the stale step passed through the card-id guard.
	if step_matches:
		assert_int(planner._plan_turn).is_equal(3)
		assert_bool(planner._plan.is_empty()).is_false() # replan produced a full line + PASS
