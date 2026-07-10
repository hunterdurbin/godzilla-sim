extends GdUnitTestSuite

## KAIJU plan sub-decision replay: KaijuRolloutInput records the answers it
## gives inside rollouts, KaijuPlanner stores them per plan step, and the
## live BotPlayer consumes them via the scripted-decision queue (falling back
## to heuristics on any mismatch).

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
	return state


func _make_bot(state: GameState) -> BotPlayer:
	var bot := BotPlayer.new()
	bot.bot_player_id = 1
	bot.config = BotConfig.kaiju()
	bot.config.kaiju_beam_width = 2
	bot.config.kaiju_max_depth = 2
	bot.config.kaiju_node_budget = 24
	bot.game_state = state
	return bot


# --- Recording (rollout side) ---


func test_rollout_input_records_planner_side_answers() -> void:
	# Use a real rollout: its input's policy bot is fully wired to the scratch
	# engine (a bare BotPlayer would null-crash inside the scorers and abort
	# the awaiting coroutine — the typed/dynamic-call hang gotcha).
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	var input := rollout.tm.player_input as KaijuRolloutInput

	var choice: int = await input.choose_option(1, ["Option A", "Skip"] as Array[String], "")
	var strategy: int = await input.select_strategy(1, 1, [0, 1] as Array[int], "")
	var discards: Array[int] = await input.choose_hand_discards(1, 1, 4)

	assert_int(input.decision_log.size()).is_equal(3)
	assert_that(input.decision_log[0]).is_equal({"m": "choice", "v": choice})
	assert_that(input.decision_log[1]).is_equal({"m": "strategy", "v": strategy})
	assert_that(input.decision_log[2]).is_equal({"m": "hand_discard", "v": discards})
	rollout.release()


func test_rollout_input_skips_recording_for_opponent() -> void:
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	var input := rollout.tm.player_input as KaijuRolloutInput

	await input.choose_option(0, ["Option A"] as Array[String], "")
	assert_bool(input.decision_log.is_empty()).is_true()
	rollout.release()


func test_rollout_apply_resets_decision_log() -> void:
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(_build_state()), 1, BotConfig.kaiju())
	var input := rollout.tm.player_input as KaijuRolloutInput
	input.decision_log.append({"m": "choice", "v": 0})

	var monster_indices: Array[int] = rollout.rules().get_monster_cards_for_rage(rollout.state().players[1])
	await rollout.apply(CardEnums.ActionType.GAIN_RAGE, {"hand_index": monster_indices[0]})

	# GAIN_RAGE asks no sub-questions; the stale entry must be gone.
	assert_bool(rollout.decisions().is_empty()).is_true()
	rollout.release()


# --- Plan storage (planner side) ---


func test_plan_steps_carry_sub_decisions() -> void:
	var state := _build_state()
	for m in CardData.get_monster_deck(CardEnums.CardTrait.GODZILLA):
		if m.get("rank", 0) > 1:
			state.players[1].monster_deck.append(m.duplicate(true))
	var bot := _make_bot(state)
	var planner := KaijuPlanner.new(bot)
	await planner.decide_action([])

	# Every remaining cached step (incl. the terminal PASS) has the key.
	assert_bool(planner._plan.is_empty()).is_false()
	for step in planner._plan:
		assert_bool(step.has("sub_decisions")).is_true()
		assert_bool(step["sub_decisions"] is Array).is_true()


func test_cache_hit_primes_bot_scripted_queue() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	planner._plan_turn = 3
	planner._plan = [{
		"action": CardEnums.ActionType.GAIN_RAGE, "params": {"hand_index": 3},
		"predicted_hash": StateCodec.compute_state_hash(bot.game_state),
		"card_id": GODZILLA_R1,
		"sub_decisions": [{"m": "choice", "v": 1}],
	}]

	await planner.decide_action([])
	assert_that(bot._pop_scripted("choice")).is_equal(1)


# --- Live consumption (bot side) ---


func test_pop_scripted_consumes_in_order() -> void:
	var bot := _make_bot(_build_state())
	bot._prime_scripted_decisions([{"m": "choice", "v": 2}, {"m": "zone", "v": 4}])

	assert_that(bot._pop_scripted("choice")).is_equal(2)
	assert_that(bot._pop_scripted("zone")).is_equal(4)
	assert_that(bot._pop_scripted("zone")).is_null()


func test_pop_scripted_kind_mismatch_clears_queue() -> void:
	var bot := _make_bot(_build_state())
	bot._prime_scripted_decisions([{"m": "choice", "v": 2}, {"m": "zone", "v": 4}])

	# Live asked a different question first: the whole script is stale.
	assert_that(bot._pop_scripted("hand_discard")).is_null()
	assert_that(bot._pop_scripted("choice")).is_null()


func test_prime_with_empty_clears_leftovers() -> void:
	var bot := _make_bot(_build_state())
	bot._prime_scripted_decisions([{"m": "choice", "v": 2}])
	bot._prime_scripted_decisions([])
	assert_that(bot._pop_scripted("choice")).is_null()


# --- Live-side validators ---


func test_find_card_by_id_prefers_exact_instance_then_base() -> void:
	var bot := _make_bot(_build_state())
	var cards: Array[Dictionary] = [
		{"id": "ESD01-008_0_1"}, {"id": "ESD01-008_0_2"}, {"id": "ESD01-020_0_0"},
	]
	assert_that(bot._find_card_by_id(cards, "ESD01-008_0_2").get("id")).is_equal("ESD01-008_0_2")
	# Different copy of the same base card still matches.
	assert_that(bot._find_card_by_id(cards, "ESD01-020_1_3").get("id")).is_equal("ESD01-020_0_0")
	assert_bool(bot._find_card_by_id(cards, "EBP04-001_0_0").is_empty()).is_true()


func test_scripted_deck_arrange_requires_exact_cover() -> void:
	var bot := _make_bot(_build_state())
	var cards: Array[Dictionary] = [{"id": "A_0_0"}, {"id": "B_0_0"}, {"id": "C_0_0"}]

	var ok := bot._scripted_deck_arrange(cards, {"keep": ["B_0_0", "A_0_0"], "discard": ["C_0_0"]})
	assert_that(ok.get("keep")[0].get("id")).is_equal("B_0_0")
	assert_int(ok.get("discard").size()).is_equal(1)

	# Missing a live card → reject (fall back to heuristic arrangement).
	assert_bool(bot._scripted_deck_arrange(cards, {"keep": ["A_0_0"], "discard": ["C_0_0"]}).is_empty()).is_true()
	# Referencing a card that is not in the live list → reject.
	assert_bool(bot._scripted_deck_arrange(cards, {"keep": ["A_0_0", "B_0_0"], "discard": ["X_0_0"]}).is_empty()).is_true()


func test_valid_scripted_indices_and_zones() -> void:
	var bot := _make_bot(_build_state())
	assert_bool(bot._valid_scripted_indices([2, 0], 2, 4)).is_true()
	assert_bool(bot._valid_scripted_indices([2, 2], 2, 4)).is_false() # duplicate
	assert_bool(bot._valid_scripted_indices([4], 1, 4)).is_false() # out of range
	assert_bool(bot._valid_scripted_indices([0], 2, 4)).is_false() # wrong count

	var valid: Array[int] = [1, 3, 5]
	assert_bool(bot._valid_scripted_zones([3, 1], valid, 2, false)).is_true()
	assert_bool(bot._valid_scripted_zones([3], valid, 2, true)).is_true() # up-to allows fewer
	assert_bool(bot._valid_scripted_zones([3], valid, 2, false)).is_false() # exact mode
	assert_bool(bot._valid_scripted_zones([2], valid, 1, true)).is_false() # not a valid zone
