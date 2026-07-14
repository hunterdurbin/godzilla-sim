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
		bot._prime_scripted_decisions(step.get("sub_decisions", []))
		if _debug:
			print("[Kaiju] t%d CACHED -> %s %s" % [gs.turn_number, CardEnums.ActionType.keys()[step["action"]], step["params"]])
		return [step["action"], step["params"]]
	if _debug and _plan_turn == gs.turn_number and not _plan.is_empty():
		print("[Kaiju] t%d plan DIVERGED (hash/card mismatch), replanning" % gs.turn_number)
	_plan.clear()

	# Root-state counter ceiling for this deliberation. Computed BEFORE the
	# planner fence: the oracle self-fences (seeds from its composition key,
	# restores a derived stream), so _search's stream below stays fully
	# determined by the planner fence either way.
	_evaluator.turn_counter_ceiling = bot.max_counter_power_remaining() \
			if bot.config.kaiju_use_counter_oracle else -1

	var fence: int = hash([live_hash, gs.turn_number, "kaiju"])
	seed(fence)
	_plan = await _search(bot, gs)
	seed(hash([fence, _POST_FENCE_SALT]))

	_plan_turn = gs.turn_number
	var first: Dictionary = _plan.pop_front()
	bot._prime_scripted_decisions(first.get("sub_decisions", []))
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

	var snap := KaijuRollout.determinize(KaijuRollout.snapshot(gs, bot.effect_handler), 1 - pid, config.kaiju_info_visibility)
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
	# Top end-of-turn candidates kept for opponent-reply re-scoring:
	# {"steps", "score", "snap"} — or {"steps", "score", "terminal": true} for
	# lines that already ended the game.
	var use_opp_ply: bool = config.kaiju_opponent_ply
	var finalists: Array[Dictionary] = []
	# Best line containing no INVADE action — forced into the reply pass when
	# invade-heavy lines fill the pool, so "play slow" gets ply-tested. Only
	# for LOW-viability decks: a deck that can finish the race should race
	# (measured: forcing slow lines on a high-viability mirror costs ~16 win
	# points vs HARD — the 1-turn reply horizon undervalues sustained tempo),
	# while a deck that can't clear the zone-8 blocker needs the slow line
	# in the comparison.
	var viability: float = float(config.kaiju_deck_profile.get("invasion_viability", 1.0))
	var force_slow_line: bool = use_opp_ply and viability < 0.5
	var best_no_invade: Dictionary = {}

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
			if use_opp_ply and _finalist_qualifies(finalists, config, stop_score):
				_offer_finalist(finalists, config,
						{"steps": steps.duplicate(), "score": stop_score, "snap": rollout.capture()})
			if force_slow_line and not _line_has_invade(steps) \
					and (best_no_invade.is_empty() or stop_score > best_no_invade["score"]):
				best_no_invade = {"steps": steps.duplicate(), "score": stop_score, "snap": rollout.capture()}

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
					if use_opp_ply and _finalist_qualifies(finalists, config, score):
						# Game already over — no opponent reply exists.
						_offer_finalist(finalists, config,
								{"steps": branch_steps, "score": score, "terminal": true})
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

	# Opponent-reply pass: revive the top finalists, play out our PASS + a
	# greedy opponent turn (incl. their counter phase against us), and pick
	# the line by post-reply score. Catches one-turn opponent CP spikes and
	# lethal counter setups the analytic leaf model underestimates.
	if use_opp_ply and not finalists.is_empty() and best_score < KaijuEvaluator.WIN_SCORE:
		# Guarantee at least one non-invade line gets ply-tested.
		if not best_no_invade.is_empty():
			var pool_has_no_invade := false
			for f in finalists:
				if not _line_has_invade(f["steps"]):
					pool_has_no_invade = true
					break
			if not pool_has_no_invade:
				finalists.append(best_no_invade) # one extra slot beyond the cap
		var best_post: float = -INF
		for f in finalists:
			var post: float
			if f.get("terminal", false):
				post = f["score"]
			else:
				# Deliberately NOT gated on the node budget: the reply pass has
				# its own deterministic bound (kaiju_finalists ×
				# kaiju_opponent_reply_actions) and is the whole point of the
				# search — a beam that ate the budget must not starve it. The
				# wall-clock check still protects live-play responsiveness.
				if use_time_budget and Time.get_ticks_msec() - start_ms > config.kaiju_time_budget_ms:
					break # finalists are analytic-best-first; the tail loses by default
				if bot.scene_tree != null and config.action_delay > 0.0:
					await bot.scene_tree.process_frame
				var reply := KaijuRollout.new(f["snap"], pid, config, bot.playstyle)
				expansions += await reply.play_opponent_reply(config.kaiju_opponent_reply_actions)
				post = _evaluator.evaluate(reply, pid, phase)
				reply.release()
			if _debug:
				var step_names: Array = []
				for s in f["steps"]:
					step_names.append(CardEnums.ActionType.keys()[s["action"]])
				print("[Kaiju]   finalist %s analytic=%.1f post=%.1f" % [step_names, f["score"], post])
			if post > best_post:
				best_post = post
				best_steps = f["steps"]

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
		"predicted_hash": check_hash, "card_id": "", "sub_decisions": [],
	})
	return best_steps


func _line_has_invade(steps: Array[Dictionary]) -> bool:
	for step in steps:
		if step["action"] == CardEnums.ActionType.INVADE:
			return true
	return false


## Would a line with this analytic score enter the finalist pool? Checked
## before the (comparatively expensive) state snapshot.
func _finalist_qualifies(finalists: Array[Dictionary], config: BotConfig, score: float) -> bool:
	var cap: int = maxi(1, config.kaiju_finalists)
	return finalists.size() < cap or score > finalists[finalists.size() - 1]["score"]


## Insert a finalist, keeping the pool sorted best-first and capped.
func _offer_finalist(finalists: Array[Dictionary], config: BotConfig, entry: Dictionary) -> void:
	var cap: int = maxi(1, config.kaiju_finalists)
	finalists.append(entry)
	finalists.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	while finalists.size() > cap:
		finalists.pop_back()


func _make_step(cand: Dictionary, branch: KaijuRollout) -> Dictionary:
	return {
		"action": cand["action"],
		"params": cand["params"],
		# Hash of the state we expect to SEE when asked for the step AFTER
		# this one — recorded on the previous step's completion.
		"predicted_hash": branch.state_hash(),
		"card_id": cand.get("card_id", ""),
		# Mid-effect answers the rollout gave while executing this action; the
		# live bot replays them so the plan's line survives into the real game.
		"sub_decisions": branch.decisions().duplicate(true),
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

	# Combo awareness: inject the active combo's forced next action as the
	# first candidate and keep its reserved pieces out of the generic pools
	# (same protection the HARD ladder applies in _decide_main_action).
	var combo_reserved: Array[int] = []
	var invade_excludes: Array[int] = []
	if not policy._combos.is_empty():
		policy._active_combo_plan = {}
		policy._ensure_combo_plan()
		combo_reserved = policy._get_combo_reserved_indices()
		invade_excludes = policy._get_combo_invasion_excludes()
		var combo_action: Array = policy._get_combo_execution_action(valid, player, opponent)
		if combo_action.size() == 2 and combo_action[0] in valid:
			var combo_params: Dictionary = combo_action[1]
			var combo_card: Dictionary = {}
			var combo_idx: int = combo_params.get("hand_index", -1)
			if combo_idx >= 0 and combo_idx < player.hand.size():
				combo_card = player.hand[combo_idx]
			out.append(_candidate(combo_action[0], combo_params, combo_card))

	if CardEnums.ActionType.PLAY_MONSTER in valid:
		for idx in re.get_playable_monsters(player):
			out.append(_candidate(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": idx}, player.hand[idx]))

	if CardEnums.ActionType.PLAY_STRATEGY in valid:
		var strategy_pool := re.get_playable_strategy_cards(player).filter(
				func(idx: int) -> bool: return idx not in combo_reserved)
		var strategy_order := _score_hand_indices(strategy_pool, policy, player, opponent, near_winning, z8_blocked)
		for i in range(mini(config.kaiju_strategy_candidates, strategy_order.size())):
			var idx: int = strategy_order[i]
			out.append(_candidate(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": idx}, player.hand[idx]))

	if CardEnums.ActionType.PLAY_BATTLE in valid:
		var battle_pool := re.get_playable_battle_cards(player, opponent).filter(
				func(idx: int) -> bool: return idx not in combo_reserved)
		var battle_order := _score_hand_indices(battle_pool, policy, player, opponent, near_winning, z8_blocked)
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

	# Cycling: when we're not countering this turn anyway, dumping the weakest
	# playable battle card onto an occupied own zone (overload, rule 11.5)
	# converts a known-weak card into an end-phase refill draw — the human
	# tempo technique of playing into the same zone to cycle into better
	# cards. The zone picker never proposes occupied zones, so this is a
	# genuinely new line; the refill-aware hand_diff lets it evaluate fairly
	# and the search decides whether the fresh draw beats keeping the card.
	if CardEnums.ActionType.PLAY_BATTLE in valid and not policy.can_counter_opponent():
		var cycle_pool: Array[int] = []
		cycle_pool.assign(re.get_playable_battle_cards(player, opponent).filter(
				func(idx: int) -> bool: return idx not in combo_reserved))
		if not cycle_pool.is_empty():
			var dump_idx: int = cycle_pool[0]
			for idx in cycle_pool:
				if policy._card_sort_value(player.hand[idx]) < policy._card_sort_value(player.hand[dump_idx]):
					dump_idx = idx
			var dump_card: Dictionary = player.hand[dump_idx]
			var queries: EffectQueries = rollout.queries()
			var dump_zone: int = -1
			var dump_zone_cp: int = 0
			for z in re.get_valid_zones_for_card(dump_card, player, opponent):
				if not player.zone_has_cards(z):
					continue
				if rollout.tm.effect_handler.should_stack_on_play(pid, dump_card, z):
					continue # stacking keeps the old card — not a cycle
				var cp: int = queries.get_effective_zone_cp(pid, z)
				if dump_zone < 0 or cp < dump_zone_cp:
					dump_zone = z
					dump_zone_cp = cp
			if dump_zone >= 0:
				out.append(_candidate(CardEnums.ActionType.PLAY_BATTLE,
						{"hand_index": dump_idx, "zone_index": dump_zone}, dump_card))

	if CardEnums.ActionType.GAIN_RAGE in valid:
		var rage_indices: Array[int] = []
		rage_indices.assign(re.get_monster_cards_for_rage(player).filter(
				func(idx: int) -> bool: return idx not in combo_reserved))
		if not rage_indices.is_empty():
			var worst: int = rage_indices[0]
			for idx in rage_indices:
				if policy._card_sort_value(player.hand[idx]) < policy._card_sort_value(player.hand[worst]):
					worst = idx
			out.append(_candidate(CardEnums.ActionType.GAIN_RAGE, {"hand_index": worst}, player.hand[worst]))

	if CardEnums.ActionType.INVADE in valid:
		var invade_indices: Array[int] = []
		invade_indices.assign(re.get_discardable_cards_for_invade(player, opponent).filter(
				func(idx: int) -> bool: return idx not in invade_excludes))
		for steps_wanted in [2, 1]:
			var best_idx: int = -1
			for idx in invade_indices:
				if mini(player.hand[idx].get("invasion_icon", 0), 2) != steps_wanted:
					continue
				if best_idx < 0 or _invade_cost_key(player.hand[idx], opponent, policy) \
						< _invade_cost_key(player.hand[best_idx], opponent, policy):
					best_idx = idx
			if best_idx >= 0:
				out.append(_candidate(CardEnums.ActionType.INVADE, {"hand_index": best_idx}, player.hand[best_idx]))

	return _dedupe_candidates(out)


## The combo's forced action can repeat a generic candidate; keep first
## occurrence (order is deterministic, so this preserves reproducibility).
func _dedupe_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var unique: Array[Dictionary] = []
	for cand in candidates:
		var key := "%d|%s" % [cand["action"], cand["params"]]
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(cand)
	return unique


## Invade discard preference: bricked battle cards first (rank locked out by
## the opponent monster's zone, rule 8.2 — invasion cost is their main
## outlet since rage fodder must be monsters), then the classic lowest sort
## value. Lower key = better cost.
func _invade_cost_key(card: Dictionary, opponent: PlayerState, policy: BotPlayer) -> int:
	var bricked: bool = card.get("card_type") == CardEnums.CardType.BATTLE \
			and int(card.get("rank", 0)) > opponent.monster_zone + 1
	return policy._card_sort_value(card) - (100000000 if bricked else 0)


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
