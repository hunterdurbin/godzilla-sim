extends GdUnitTestSuite

## KaijuRollout.play_opponent_reply — the scratch match advances through our
## PASS (counter/end), the opponent's full greedy turn, and lands at our next
## main phase (or game over), synchronously and deterministically.

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
		for i in range(4):
			p.hand.append(battle.duplicate(true))
		for i in range(8):
			p.main_deck.append(battle.duplicate(true))
		p.hand.append(monster.duplicate(true))
		for m in CardData.get_monster_deck(CardEnums.CardTrait.GODZILLA):
			if m.get("rank", 0) > 1:
				p.monster_deck.append(m.duplicate(true))
	return state


func test_opponent_reply_lands_at_our_next_main_or_game_over() -> void:
	seed(4242)
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	var used: int = await rollout.play_opponent_reply(10)

	assert_int(used).is_greater_equal(1)
	if not rollout.is_over():
		# Back on the planner's turn, main phase, awaiting action.
		assert_int(rollout.state().current_player_id).is_equal(1)
		assert_int(int(rollout.state().current_phase)).is_equal(int(CardEnums.GamePhase.MAIN))
		# Two turn transitions happened: ours ended, theirs ran to completion.
		assert_int(rollout.state().turn_number).is_equal(5)
	rollout.release()


func test_opponent_reply_is_deterministic_per_seed() -> void:
	var snap := KaijuRollout.snapshot(_build_state())

	seed(999)
	var a := KaijuRollout.new(snap, 1, BotConfig.kaiju())
	await a.play_opponent_reply(10)
	var hash_a: int = a.state_hash()
	var over_a: bool = a.is_over()
	a.release()

	seed(999)
	var b := KaijuRollout.new(snap, 1, BotConfig.kaiju())
	await b.play_opponent_reply(10)

	assert_bool(b.is_over()).is_equal(over_a)
	assert_int(b.state_hash()).is_equal(hash_a)
	b.release()


func test_opponent_reply_clears_opponent_policy_reference() -> void:
	seed(4242)
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	await rollout.play_opponent_reply(10)
	var input := rollout.tm.player_input as KaijuRolloutInput
	assert_object(input.opponent_policy).is_null()
	rollout.release()


func test_planner_with_opponent_ply_still_returns_legal_plan() -> void:
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.config = BotConfig.kaiju()
	bot.config.kaiju_beam_width = 2
	bot.config.kaiju_max_depth = 2
	bot.config.kaiju_node_budget = 60
	bot.config.kaiju_opponent_ply = true
	bot.config.kaiju_finalists = 2
	bot.game_state = _build_state()
	var planner := KaijuPlanner.new(bot)

	var result: Array = await planner.decide_action([])
	assert_int(result.size()).is_equal(2)
	var valid: Array = [
		CardEnums.ActionType.PLAY_BATTLE, CardEnums.ActionType.PLAY_STRATEGY,
		CardEnums.ActionType.GAIN_RAGE, CardEnums.ActionType.PLAY_MONSTER,
		CardEnums.ActionType.INVADE, CardEnums.ActionType.PASS,
	]
	assert_bool(result[0] in valid).is_true()
