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


# --- v1.2: deck viability / draw tempo / race restraint / opponent profile ---


func _score_with(state: GameState, config: BotConfig) -> float:
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
	var score := KaijuEvaluator.new(config).evaluate(rollout, 1, "mid")
	rollout.release()
	return score


func test_low_invasion_viability_devalues_zone_lead() -> void:
	var state := _build_state(6, 2, 0)
	var neutral := _score_with(state, BotConfig.kaiju())
	var low := BotConfig.kaiju()
	low.kaiju_deck_profile = {"invasion_viability": 0.05, "clear_capability": 0.0}
	assert_bool(_score_with(state, low) < neutral).is_true()


func test_zone8_block_hurts_more_without_destruction() -> void:
	var state := _build_state(6, 2, 0)
	# Opponent battle card in zone 8 blocks our winning invasion.
	state.players[0].push_zone_card(7, CardData.get_card_by_id(VANILLA_BATTLE))
	var can_clear := BotConfig.kaiju()
	can_clear.kaiju_deck_profile = {"invasion_viability": 0.5, "clear_capability": 1.0}
	var cannot_clear := BotConfig.kaiju()
	cannot_clear.kaiju_deck_profile = {"invasion_viability": 0.5, "clear_capability": 0.0}
	assert_bool(_score_with(state, cannot_clear) < _score_with(state, can_clear)).is_true()


## Both monsters at z6+, we lead the race with an invade card in hand, and
## our board CP crosses their threat: the mandatory counter is priced as a
## race loss, so the default weight scores it lower than a zeroed one.
func _race_state() -> GameState:
	var state := _build_state(7, 0, 0)
	state.players[0].monster_zone = 6
	var invade_card: Dictionary = CardData.get_card_by_id("ESD01-013") # invasion_icon 1
	state.players[1].hand.append(invade_card.duplicate(true))
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	for i in range(4): # 8000 CP > their 6000 threat: our counter WILL fire
		state.players[1].push_zone_card(i, battle.duplicate(true))
	return state


func test_race_counter_restraint_devalues_forced_counter() -> void:
	var state := _race_state()
	var default_cfg := BotConfig.kaiju()
	var no_restraint := BotConfig.kaiju()
	no_restraint.kaiju_eval_weights["mid"]["race_counter_restraint"] = 0.0
	assert_bool(_score_with(state, default_cfg) < _score_with(state, no_restraint)).is_true()


func test_counter_victory_shortcut_survives_race_restraint() -> void:
	var state := _race_state()
	state.players[0].monster_deck.clear() # they can't rank up: countering WINS
	var config := BotConfig.kaiju()
	assert_float(_score_with(state, config)).is_equal(KaijuEvaluator.WIN_SCORE * 0.5)


func test_draw_tempo_rewards_higher_opponent_rank() -> void:
	# Isolate the term: zero every weight except draw_tempo.
	var config := BotConfig.kaiju()
	var zeroed: Dictionary = {}
	for key in config.kaiju_eval_weights["mid"]:
		zeroed[key] = 0.0
	zeroed["draw_tempo"] = 6.0
	config.kaiju_eval_weights["mid"] = zeroed

	var rank1 := _build_state(3, 0, 0)
	var rank2 := _build_state(3, 0, 0)
	for m in CardData.get_monster_deck(CardEnums.CardTrait.GODZILLA):
		if m.get("rank", 0) == 2:
			rank2.players[0].current_monster = m.duplicate(true)
			break
	assert_bool(_score_with(rank2, config) > _score_with(rank1, config)).is_true()


func test_hand_bricks_penalize_unplayable_cards() -> void:
	# Isolate the term: opponent monster at zone 3, a rank-6 battle card in
	# hand is a brick (needs THEIR zone >= 6 to play, rule 8.2).
	var config := BotConfig.kaiju()
	var zeroed: Dictionary = {}
	for key in config.kaiju_eval_weights["mid"]:
		zeroed[key] = 0.0
	zeroed["hand_bricks"] = 8.0
	config.kaiju_eval_weights["mid"] = zeroed

	var clean := _build_state(3, 0, 0)
	var bricked := _build_state(3, 0, 0)
	bricked.players[1].hand.append(CardData.get_card_by_id("ESD01-010").duplicate(true)) # battle rank 6
	assert_bool(_score_with(bricked, config) < _score_with(clean, config)).is_true()


func _isolated_config(key: String, weight: float) -> BotConfig:
	var config := BotConfig.kaiju()
	var zeroed: Dictionary = {}
	for k in config.kaiju_eval_weights["mid"]:
		zeroed[k] = 0.0
	zeroed[key] = weight
	config.kaiju_eval_weights["mid"] = zeroed
	return config


func test_rankups_diff_prices_lives_exchange() -> void:
	# Same board, but 0-vs-2 rank-ups must score below 2-vs-2: win-condition
	# proximity is relative — the human tracks BOTH lives pools.
	var config := _isolated_config("rankups_diff", 60.0)
	var even := _build_state(5, 0, 0)
	var spent := _build_state(5, 0, 0)
	spent.players[1].monster_deck.clear()
	assert_bool(_score_with(spent, config) < _score_with(even, config)).is_true()


func test_z8_dead_end_penalizes_pathless_camping() -> void:
	# Bot at z7 with the opponent's zone 8 occupied: without any destroys_zone
	# answer the invasion win does not exist — with one in hand it does.
	var config := _isolated_config("z8_dead_end", 150.0)
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)

	var pathless := _build_state(7, 0, 0)
	pathless.players[0].push_zone_card(7, battle.duplicate(true)) # their z8 blocker
	var armed := _build_state(7, 0, 0)
	armed.players[0].push_zone_card(7, battle.duplicate(true))
	armed.players[1].hand.append(CardData.get_card_by_id("ESD01-006").duplicate(true)) # destroys_zone

	assert_bool(_score_with(pathless, config) < _score_with(armed, config)).is_true()


func test_cycle_filter_rewards_dumped_hand_on_non_counter_turns() -> void:
	var config := _isolated_config("cycle_filter", 3.0)
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)

	var full := _build_state(3, 0, 0)
	var dumped := _build_state(3, 0, 0)
	var starved := _build_state(3, 0, 0)
	for state in [full, dumped, starved]:
		state.players[1].hand.clear()
		state.players[1].hand.append(battle.duplicate(true))
	for i in range(4):
		full.players[1].hand.append(battle.duplicate(true))
	starved.players[1].main_deck.clear() # no refill → no filter value

	# Cannot counter in all three states (board CP 0 vs threat) → gate open.
	assert_bool(_score_with(dumped, config) > _score_with(full, config)).is_true()
	assert_float(_score_with(starved, config)).is_equal_approx(_score_with(full, config), 0.01)


func test_hand_diff_projects_end_phase_refill() -> void:
	# Isolate hand_diff: a dumped hand refills to 5 in the imminent end phase
	# (rule 7.5.4), so it must not score below a full hand while the deck can
	# refill — and must score lower once the deck is empty.
	var config := BotConfig.kaiju()
	var zeroed: Dictionary = {}
	for key in config.kaiju_eval_weights["mid"]:
		zeroed[key] = 0.0
	zeroed["hand_diff"] = 10.0
	config.kaiju_eval_weights["mid"] = zeroed

	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	var full := _build_state(3, 0, 0)
	var dumped := _build_state(3, 0, 0)
	var starved := _build_state(3, 0, 0)
	for state in [full, dumped, starved]:
		state.players[1].hand.clear()
	for i in range(5):
		full.players[1].hand.append(battle.duplicate(true))
	dumped.players[1].hand.append(battle.duplicate(true)) # 1 card, deck can refill
	starved.players[1].hand.append(battle.duplicate(true))
	starved.players[1].main_deck.clear() # no refill possible

	assert_float(_score_with(dumped, config)).is_equal_approx(_score_with(full, config), 0.01)
	assert_bool(_score_with(starved, config) < _score_with(dumped, config)).is_true()


func test_opponent_profile_raises_projected_counter_risk() -> void:
	# 2 opponent board cards + hand; neutral prior thinks we're safe at
	# threat 6000. A measured heavy deployer (cp_per_card 20k) is not safe.
	var state := _build_state(5, 0, 2)
	var neutral := _score_with(state, BotConfig.kaiju())
	var wary := BotConfig.kaiju()
	wary.kaiju_opponent_profile = {
		"games": 8, "cp_per_card": 20000.0, "hand_hoard": 3.0,
		"counters_per_turn": 0.5, "invade_tempo": 0.8, "early_invader": 0.0,
	}
	assert_bool(_score_with(state, wary) < neutral).is_true()
