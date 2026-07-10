class_name KaijuPlanner
extends RefCounted

## Turn-plan search for the KAIJU difficulty. On the first awaiting_action of
## a turn it beam-searches over action SEQUENCES for the whole main phase on
## cloned scratch matches (KaijuRollout), scores end-of-turn states with
## KaijuEvaluator, caches the best line, and then feeds it back one step per
## awaiting_action callback. Every step is hash-checked against the live
## state; any divergence (mid-effect handler drift, live RNG differences)
## just triggers a replan.
##
## RNG fence: rollouts consume the global RNG and Godot 4 offers no way to
## read the global RNG state back, so deliberation re-seeds deterministically
## from the position and re-seeds a derived value afterwards. Other tiers
## never enter this code; KAIJU games stay deterministic per base_seed but
## are not comparable to HARD baselines (see README.md here).

const _POST_FENCE_SALT: int = 0x9E3779B9

var _bot_ref: WeakRef
var _evaluator: KaijuEvaluator = null

# Cached plan for the current turn: [{action, params, predicted_hash, card_id}].
var _plan: Array[Dictionary] = []
var _plan_turn: int = -1

# High-water mark of the max monster zone either player has reached — the
# game-phase latch (invasion_zones_crossed is per-turn, not usable here).
var _max_zone_seen: int = 1

## Temporary diagnostics (set KAIJU_DEBUG=1 in the environment).
var _debug: bool = OS.get_environment("KAIJU_DEBUG") == "1"


func _init(bot: BotPlayer) -> void:
	_bot_ref = weakref(bot)
	_evaluator = KaijuEvaluator.new(bot.config)


func decide_action(_valid_actions: Array) -> Array:
	var bot: BotPlayer = _bot_ref.get_ref()
	if bot == null:
		return [CardEnums.ActionType.PASS, {}]
	var gs: GameState = bot.game_state
	_max_zone_seen = maxi(_max_zone_seen, maxi(gs.players[0].monster_zone, gs.players[1].monster_zone))

	var live_hash: int = StateCodec.compute_state_hash(gs)
	if _plan_turn == gs.turn_number and not _plan.is_empty() \
			and _plan[0]["predicted_hash"] == live_hash and _step_card_matches(bot, _plan[0]):
		var step: Dictionary = _plan.pop_front()
		if _debug:
			print("[Kaiju] t%d CACHED -> %s %s" % [gs.turn_number, CardEnums.ActionType.keys()[step["action"]], step["params"]])
		return [step["action"], step["params"]]
	if _debug and _plan_turn == gs.turn_number and not _plan.is_empty():
		print("[Kaiju] t%d plan DIVERGED (hash/card mismatch), replanning" % gs.turn_number)
	_plan.clear()

	var fence: int = hash([live_hash, gs.turn_number, "kaiju"])
	seed(fence)
	_plan = await _search(bot, gs)
	seed(hash([fence, _POST_FENCE_SALT]))

	_plan_turn = gs.turn_number
	var first: Dictionary = _plan.pop_front()
	if _debug:
		var names: Array = []
		for s in _plan:
			names.append(CardEnums.ActionType.keys()[s["action"]])
		print("[Kaiju] t%d z%d/%d r%d NEW PLAN -> %s %s then %s" % [gs.turn_number,
				gs.players[bot.bot_player_id].monster_zone, gs.players[1 - bot.bot_player_id].monster_zone,
				gs.players[bot.bot_player_id].rage,
				CardEnums.ActionType.keys()[first["action"]], first["params"], names])
	return [first["action"], first["params"]]


## A plan step that plays a specific hand card must still point at the same
## card in the live hand (a mid-turn draw can differ from the rollout's).
func _step_card_matches(bot: BotPlayer, step: Dictionary) -> bool:
	var card_id: String = step.get("card_id", "")
	if card_id.is_empty():
		return true
	var hand: Array = bot.game_state.players[bot.bot_player_id].hand
	var idx: int = step["params"].get("hand_index", -1)
	if idx < 0 or idx >= hand.size():
		return false
	return CardUtils.base_id(hand[idx]) == card_id


# --- Beam search ---

func _search(bot: BotPlayer, gs: GameState) -> Array[Dictionary]:
	var config: BotConfig = bot.config
	var pid: int = bot.bot_player_id
	var phase: String = KaijuEvaluator.phase_key(gs.turn_number, _max_zone_seen)
	var start_ms: int = Time.get_ticks_msec()
	# Wall-clock cutoff is inherently non-deterministic, so it only guards
	# LIVE play (frame responsiveness); headless sims/tests must stay
	# byte-reproducible and are bounded by the node budget alone.
	var use_time_budget: bool = bot.scene_tree != null and config.action_delay > 0.0
	var expansions: int = 0

	var snap := KaijuRollout.determinize(KaijuRollout.snapshot(gs), 1 - pid, config.kaiju_info_visibility)
	var root := KaijuRollout.new(snap, pid, config, bot.playstyle)
	if _debug:
		var root_cands: Array = []
		for c in _enumerate_candidates(root, pid, config):
			root_cands.append("%s%s" % [CardEnums.ActionType.keys()[c["action"]], c["params"]])
		var opp_cp_dbg: int = _evaluator._effective_counter_cp(root.queries(), root.state().players[1 - pid])
		var threat_dbg: int = root.queries().get_effective_threat_level(pid)
		print("[Kaiju]   root cands=%s oppCP=%d ourThreat=%d" % [root_cands, opp_cp_dbg, threat_dbg])

	# Beam entries: {"rollout": KaijuRollout, "steps": Array[Dictionary]}.
	var beam: Array[Dictionary] = [{"rollout": root, "steps": [] as Array[Dictionary]}]
	var best_steps: Array[Dictionary] = []
	var best_score: float = -INF
	var out_of_budget := false

	for depth in range(config.kaiju_max_depth):
		var next_beam: Array[Dictionary] = []
		for node in beam:
			var rollout: KaijuRollout = node["rollout"]
			var steps: Array[Dictionary] = node["steps"]

			# Ending the turn here is always a candidate line.
			var stop_score: float = _evaluator.evaluate(rollout, pid, phase)
			if stop_score > best_score:
				best_score = stop_score
				best_steps = steps.duplicate()

			if out_of_budget or best_score >= KaijuEvaluator.WIN_SCORE:
				continue

			for cand in _enumerate_candidates(rollout, pid, config):
				if expansions >= config.kaiju_node_budget \
						or (use_time_budget and Time.get_ticks_msec() - start_ms > config.kaiju_time_budget_ms):
					out_of_budget = true
					break
				var branch := rollout.clone()
				expansions += 1
				if bot.scene_tree != null and config.action_delay > 0.0 and expansions % 8 == 0:
					await bot.scene_tree.process_frame
				var alive: bool = await branch.apply(cand["action"], cand["params"])
				var branch_steps: Array[Dictionary] = steps.duplicate()
				branch_steps.append(_make_step(cand, branch))
				var score: float = _evaluator.evaluate(branch, pid, phase)
				if _debug and depth == 0:
					print("[Kaiju]     d0 %s%s -> %.1f (stop=%.1f)" % [CardEnums.ActionType.keys()[cand["action"]], cand["params"], score, stop_score])
				if not alive:
					if score > best_score:
						best_score = score
						best_steps = branch_steps
					branch.release()
					continue
				next_beam.append({"rollout": branch, "steps": branch_steps, "score": score})

		for node in beam:
			node["rollout"].release()
		if next_beam.is_empty() or best_score >= KaijuEvaluator.WIN_SCORE or out_of_budget:
			for node in next_beam:
				node["rollout"].release()
			break
		next_beam.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["score"] > b["score"])
		while next_beam.size() > config.kaiju_beam_width:
			next_beam.pop_back()["rollout"].release()
		beam = next_beam

	# During search each step recorded the hash AFTER it executed; the cache
	# check needs the hash expected BEFORE each step runs. Shift by one: step
	# k is checked against the state after step k-1 (the live state for step
	# 0), and the terminal PASS against the state after the last real step.
	var check_hash: int = StateCodec.compute_state_hash(gs)
	for step in best_steps:
		var after: int = step["predicted_hash"]
		step["predicted_hash"] = check_hash
		check_hash = after
	best_steps.append({
		"action": CardEnums.ActionType.PASS, "params": {},
		"predicted_hash": check_hash, "card_id": "",
	})
	return best_steps


func _make_step(cand: Dictionary, branch: KaijuRollout) -> Dictionary:
	return {
		"action": cand["action"],
		"params": cand["params"],
		# Hash of the state we expect to SEE when asked for the step AFTER
		# this one — recorded on the previous step's completion.
		"predicted_hash": branch.state_hash(),
		"card_id": cand.get("card_id", ""),
	}


## Deterministically ordered candidate actions at a rollout position.
## Heuristic pre-scoring (the existing bot scorers) prunes wide card pools to
## top-K before the expensive rollout clones.
func _enumerate_candidates(rollout: KaijuRollout, pid: int, config: BotConfig) -> Array[Dictionary]:
	var gs: GameState = rollout.state()
	var re: RulesEngine = rollout.rules()
	var policy: BotPlayer = rollout.policy
	var player: PlayerState = gs.players[pid]
	var opponent: PlayerState = gs.players[1 - pid]
	var valid: Array = re.get_valid_actions(gs)
	var near_winning := player.monster_zone >= 6
	var z8_blocked := opponent.zone_has_battle_card(7)
	var out: Array[Dictionary] = []

	if CardEnums.ActionType.PLAY_MONSTER in valid:
		for idx in re.get_playable_monsters(player):
			out.append(_candidate(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": idx}, player.hand[idx]))

	if CardEnums.ActionType.PLAY_STRATEGY in valid:
		var strategy_order := _score_hand_indices(re.get_playable_strategy_cards(player), policy, player, opponent, near_winning, z8_blocked)
		for i in range(mini(config.kaiju_strategy_candidates, strategy_order.size())):
			var idx: int = strategy_order[i]
			out.append(_candidate(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": idx}, player.hand[idx]))

	if CardEnums.ActionType.PLAY_BATTLE in valid:
		var battle_order := _score_hand_indices(re.get_playable_battle_cards(player, opponent), policy, player, opponent, near_winning, z8_blocked)
		for i in range(mini(config.kaiju_battle_candidates, battle_order.size())):
			var idx: int = battle_order[i]
			var zones: Array[int] = re.get_valid_zones_for_card(player.hand[idx], player, opponent)
			var remaining: Array[int] = zones.duplicate()
			for k in range(mini(config.kaiju_zone_candidates, zones.size())):
				var zone: int = policy._pick_battle_zone(remaining, player, opponent, player.hand[idx])
				if zone not in remaining:
					zone = remaining[0]
				out.append(_candidate(CardEnums.ActionType.PLAY_BATTLE, {"hand_index": idx, "zone_index": zone}, player.hand[idx]))
				remaining.erase(zone)

	if CardEnums.ActionType.GAIN_RAGE in valid:
		var rage_indices: Array[int] = re.get_monster_cards_for_rage(player)
		if not rage_indices.is_empty():
			var worst: int = rage_indices[0]
			for idx in rage_indices:
				if policy._card_sort_value(player.hand[idx]) < policy._card_sort_value(player.hand[worst]):
					worst = idx
			out.append(_candidate(CardEnums.ActionType.GAIN_RAGE, {"hand_index": worst}, player.hand[worst]))

	if CardEnums.ActionType.INVADE in valid:
		var invade_indices: Array[int] = re.get_discardable_cards_for_invade(player, opponent)
		for steps_wanted in [2, 1]:
			var best_idx: int = -1
			for idx in invade_indices:
				if mini(player.hand[idx].get("invasion_icon", 0), 2) != steps_wanted:
					continue
				if best_idx < 0 or policy._card_sort_value(player.hand[idx]) < policy._card_sort_value(player.hand[best_idx]):
					best_idx = idx
			if best_idx >= 0:
				out.append(_candidate(CardEnums.ActionType.INVADE, {"hand_index": best_idx}, player.hand[best_idx]))

	return out


func _candidate(action: CardEnums.ActionType, params: Dictionary, card: Dictionary) -> Dictionary:
	return {"action": action, "params": params, "card_id": CardUtils.base_id(card)}


## Hand indices sorted best-first by the classic heuristic card score.
func _score_hand_indices(indices: Array[int], policy: BotPlayer, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool) -> Array[int]:
	var scores: Dictionary = {}
	for idx in indices:
		scores[idx] = policy._score_card(player.hand[idx], player, opponent, near_winning, z8_blocked)
	var sorted: Array[int] = indices.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return scores[a] > scores[b])
	return sorted
