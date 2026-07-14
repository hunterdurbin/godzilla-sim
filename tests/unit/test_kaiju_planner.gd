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


func test_cycle_dump_candidate_when_not_countering() -> void:
	# Bot board CP 0 vs opponent threat: cannot counter → the planner offers
	# dumping the weakest playable battle card onto its own occupied zone
	# (overload cycling). The zone picker never proposes occupied zones, so
	# any occupied-zone PLAY_BATTLE candidate is the cycle line.
	var state := _build_state()
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	state.players[1].push_zone_card(0, battle.duplicate(true)) # occupied own zone
	var bot := _make_bot(state)
	var planner := KaijuPlanner.new(bot)
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, bot.config)

	assert_bool(rollout.policy.can_counter_opponent()).is_false()
	var candidates := planner._enumerate_candidates(rollout, 1, bot.config)
	var cycle_found := false
	for cand in candidates:
		if cand["action"] == CardEnums.ActionType.PLAY_BATTLE \
				and rollout.state().players[1].zone_has_cards(cand["params"]["zone_index"]):
			cycle_found = true
	assert_bool(cycle_found).is_true()
	rollout.release()


func test_no_cycle_dump_when_counter_available() -> void:
	# One occupied zone holding a 7000-CP card (>= opponent threat 6000 at
	# rage 0, so the bot WILL counter). The classic picker never proposes it
	# (overwriting 7000 CP with a 2000-CP card fails its no-loss filter), so
	# an occupied-zone candidate can only come from the cycle line — which
	# the counter gate must suppress here.
	var state := _build_state()
	state.players[0].rage = 0 # threat 6000: the 7000-CP wall counters it
	state.players[1].push_zone_card(0, CardData.get_card_by_id("ESD01-012").duplicate(true))
	var bot := _make_bot(state)
	var planner := KaijuPlanner.new(bot)
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 1, bot.config)

	assert_bool(rollout.policy.can_counter_opponent()).is_true()
	var candidates := planner._enumerate_candidates(rollout, 1, bot.config)
	for cand in candidates:
		if cand["action"] == CardEnums.ActionType.PLAY_BATTLE:
			assert_bool(rollout.state().players[1].zone_has_cards(cand["params"]["zone_index"])).is_false()
	rollout.release()


func test_line_has_invade_detects_invade_steps() -> void:
	var bot := _make_bot(_build_state())
	var planner := KaijuPlanner.new(bot)
	var invade_line: Array[Dictionary] = [
		{"action": CardEnums.ActionType.PLAY_BATTLE, "params": {}},
		{"action": CardEnums.ActionType.INVADE, "params": {}},
	]
	var slow_line: Array[Dictionary] = [
		{"action": CardEnums.ActionType.PLAY_BATTLE, "params": {}},
		{"action": CardEnums.ActionType.GAIN_RAGE, "params": {}},
	]
	assert_bool(planner._line_has_invade(invade_line)).is_true()
	assert_bool(planner._line_has_invade(slow_line)).is_false()
	assert_bool(planner._line_has_invade([] as Array[Dictionary])).is_false()


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
