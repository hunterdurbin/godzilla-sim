extends GdUnitTestSuite

## KaijuEvaluator — phase latching and directional (monotonicity) checks on
## the end-of-turn evaluation. Values are relative by design: the weights are
## tunable, so tests assert ordering, never absolute scores.

const GODZILLA_R1 := "ESD01-001" # rank 1 monster, threat 6000
const VANILLA_BATTLE := "ESD01-008" # battle, CP 2000, no effect script


func _build_state(p1_zone: int, p1_rage: int, p0_board_cards: int) -> GameState:
	var monster: Dictionary = CardData.get_card_by_id(GODZILLA_R1)
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	var state := GameState.new()
	state.turn_number = 5
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_sub_phase = 1
	for pid in range(2):
		var p := state.players[pid]
		p.current_monster = monster.duplicate(true)
		p.monster_zone = 3 if pid == 0 else p1_zone
		p.rage = 0 if pid == 0 else p1_rage
		p.hand.append(battle.duplicate(true))
		p.main_deck.append(battle.duplicate(true))
		# Rank-up line available so counter risk isn't a soft terminal.
		for m in CardData.get_monster_deck(CardEnums.CardTrait.GODZILLA):
			if m.get("rank", 0) > 1:
				p.monster_deck.append(m.duplicate(true))
	for i in range(p0_board_cards):
		state.players[0].push_zone_card(i, battle.duplicate(true))
	return state


func _score(state: GameState) -> float:
	var config := BotConfig.kaiju()
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
	var score := KaijuEvaluator.new(config).evaluate(rollout, 1, "mid")
	rollout.release()
	return score


func test_more_zone_progress_scores_higher() -> void:
	var behind := _score(_build_state(3, 2, 0))
	var ahead := _score(_build_state(6, 2, 0))
	assert_bool(ahead > behind).is_true()


func test_counterable_position_scores_lower() -> void:
	# Rage 0 → threat 6000; four 2000-CP cards on the opponent board → 8000 CP
	# clears it, so we'd be countered next phase.
	var safe := _score(_build_state(5, 0, 2))
	var counterable := _score(_build_state(5, 0, 4))
	assert_bool(counterable < safe).is_true()


func test_rage_buffer_beats_none_under_counter_threat() -> void:
	# Same opponent board; rage 2 lifts threat to 16000 and out of counter range.
	var exposed := _score(_build_state(5, 0, 4))
	var buffered := _score(_build_state(5, 2, 4))
	assert_bool(buffered > exposed).is_true()


func test_phase_key_latches_on_zone_high_water_mark() -> void:
	assert_str(KaijuEvaluator.phase_key(2, 1)).is_equal("early")
	assert_str(KaijuEvaluator.phase_key(2, 4)).is_equal("mid")
	assert_str(KaijuEvaluator.phase_key(2, 7)).is_equal("late")
	# Turn thresholds keep the latch even when zones regress.
	assert_str(KaijuEvaluator.phase_key(5, 1)).is_equal("mid")
	assert_str(KaijuEvaluator.phase_key(14, 1)).is_equal("late")


func test_win_and_loss_are_terminal() -> void:
	var state := _build_state(5, 2, 0)
	var config := BotConfig.kaiju()
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
	var evaluator := KaijuEvaluator.new(config)
	# Force a game-over on the scratch match and check both signs.
	rollout.tm.game_state.game_over.emit(1, "test")
	assert_float(evaluator.evaluate(rollout, 1, "mid")).is_equal(KaijuEvaluator.WIN_SCORE)
	assert_float(evaluator.evaluate(rollout, 0, "mid")).is_equal(-KaijuEvaluator.WIN_SCORE)
	rollout.release()
