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


# --- Opponent next-turn zone projection + lethal-next-turn pricing ---


## Direct helper checks: invade_steps is passed explicitly, so each case pins
## one branch (COUNTS estimation itself is covered by the integration tests).
func _projection(state: GameState, invade_steps: float) -> int:
	var config := BotConfig.kaiju()
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
	var rs: GameState = rollout.state()
	var projected: int = KaijuEvaluator.new(config)._projected_opp_zone(
			rollout.queries(), rs.players[1], rs.players[0], 1, invade_steps)
	rollout.release()
	return projected


func test_projected_opp_zone_invade_plus_advance() -> void:
	var state := _build_state(3, 0, 0)
	state.players[0].monster_zone = 5
	assert_int(_projection(state, 1.0)).is_equal(7) # invade 1 + advance 1
	assert_int(_projection(state, 0.0)).is_equal(6) # advance only
	assert_int(_projection(state, 2.0)).is_equal(8) # 5+2=7, advance caps at 8


func test_projected_opp_zone_advance_never_crosses() -> void:
	# At zone 8 with no invade the end-phase advance never crosses (the
	# advance loop breaks past zone 7) — only invasion can win.
	var state := _build_state(3, 0, 0)
	state.players[0].monster_zone = 8
	assert_int(_projection(state, 0.0)).is_equal(8)


func test_projected_opp_zone_lethal_and_zone8_block() -> void:
	var state := _build_state(3, 0, 0)
	state.players[0].monster_zone = 8
	assert_int(_projection(state, 1.0)).is_equal(9) # crossing wins
	# Our zone-8 battle card blocks the crossing: caps at 8.
	var blocked := _build_state(3, 0, 0)
	blocked.players[0].monster_zone = 8
	blocked.players[1].push_zone_card(7, CardData.get_card_by_id(VANILLA_BATTLE).duplicate(true))
	assert_int(_projection(blocked, 1.0)).is_equal(8)


func test_expected_invade_steps_full_visibility_reads_icons() -> void:
	# FULL visibility reads the opponent's actual hand: a 2-icon card projects
	# a 2-zone invade (7 + 2 crosses past 8 -> lethal). Must be a REAL card —
	# the rollout snapshot round-trips cards through the serializer.
	var state := _build_state(3, 0, 0)
	state.players[0].monster_zone = 7
	state.players[0].hand.append(CardData.get_card_by_id("ESD01-012").duplicate(true)) # invasion_icon 2
	var config := BotConfig.kaiju()
	config.kaiju_info_visibility = BotConfig.InfoVisibility.FULL
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
	var rs: GameState = rollout.state()
	var evaluator := KaijuEvaluator.new(config)
	var steps: float = evaluator._expected_opp_invade_steps(rs.players[0])
	var projected: int = evaluator._projected_opp_zone(
			rollout.queries(), rs.players[1], rs.players[0], 1, steps)
	rollout.release()
	assert_float(steps).is_equal(2.0)
	assert_int(projected).is_equal(9)


func test_opp_lethal_penalty_prices_the_three_outs() -> void:
	# Opponent at zone 8 with a card in hand = lethal next turn (COUNTS).
	# The penalty must vanish when our zone 8 blocks the crossing, and when
	# our board CP counters them this turn.
	var config := _isolated_config("opp_lethal_penalty", 400.0)

	var lethal := _build_state(3, 0, 0)
	lethal.players[0].monster_zone = 8

	var blocked := _build_state(3, 0, 0)
	blocked.players[0].monster_zone = 8
	blocked.players[1].push_zone_card(7, CardData.get_card_by_id(VANILLA_BATTLE).duplicate(true))

	# 4 x 2000 CP >= their 6000 threat: our counter fires this turn. Their
	# monster_deck stays populated (fixture default), so the counter-victory
	# WIN_SCORE shortcut doesn't preempt the comparison.
	var countering := _build_state(3, 0, 0)
	countering.players[0].monster_zone = 8
	for i in range(4):
		countering.players[1].push_zone_card(i, CardData.get_card_by_id(VANILLA_BATTLE).duplicate(true))

	var lethal_score := _score_with(lethal, config)
	assert_bool(lethal_score < _score_with(blocked, config)).is_true()
	assert_bool(lethal_score < _score_with(countering, config)).is_true()


func test_dead_counter_gate_bypassed_when_opponent_at_the_gates() -> void:
	# With the oracle ceiling below their threat and dead_counter_scale 0, the
	# cp_pressure gradient is fully suppressed — EXCEPT once the opponent
	# projects to zone 8+ next turn: from there counter pursuit is defense.
	# COUNTS projection: zone 6 + invade 1 + advance 1 = 8 (bypass boundary).
	var config := _isolated_config("cp_pressure", 0.010)
	config.kaiju_eval_weights["mid"]["dead_counter_scale"] = 0.0

	var scores: Dictionary = {}
	for opp_zone in [3, 6, 8]:
		for board_cards in [0, 2]:
			var state := _build_state(3, 0, 0)
			state.players[0].monster_zone = opp_zone
			for i in range(board_cards):
				state.players[1].push_zone_card(i, CardData.get_card_by_id(VANILLA_BATTLE).duplicate(true))
			var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, config)
			var evaluator := KaijuEvaluator.new(config)
			evaluator.turn_counter_ceiling = 0 # < their threat: gate active
			scores["%d_%d" % [opp_zone, board_cards]] = evaluator.evaluate(rollout, 1, "mid")
			rollout.release()

	# Far away (opp at 3, projects to 5): gate zeroes the gradient.
	assert_float(scores["3_2"]).is_equal_approx(scores["3_0"], 0.01)
	# At the gates (opp at 6, projects to 8): bypass keeps the gradient.
	assert_bool(scores["6_2"] > scores["6_0"]).is_true()
	# Lethal (opp at 8, projects to 9): bypass keeps the gradient.
	assert_bool(scores["8_2"] > scores["8_0"]).is_true()


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
