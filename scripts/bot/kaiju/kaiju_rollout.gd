class_name KaijuRollout
extends RefCounted

## A scratch match cloned from a live position so the KAIJU planner can
## execute candidate actions without touching the real game. Wraps exactly one
## TurnManager built via MatchFactory.setup_from_save; every code path must
## end in release() or the cyclic engine graph leaks (match-teardown
## contract). Rollouts consume the global RNG (deck reshuffles, effect
## shuffles, heuristic tiebreaks) — only create them inside the planner's
## RNG fence.

var tm: TurnManager = null
var policy: BotPlayer = null
var planner_player_id: int = 0

# Written by the game_ended lambda; a plain Dictionary captured by value so
# the signal connection never holds a reference back to this rollout.
var _result: Dictionary


## The exact subset of GameSerializer.serialize_game_state that
## MatchFactory.setup_from_save reads. Card contents are id strings,
## rehydrated to independent dicts on restore. Pass the position's
## EffectHandler so turn-scoped effect member state (e.g. "until end of
## turn" modifiers) rides along in "effect_state".
static func snapshot(gs: GameState, effect_handler: EffectHandler = null) -> Dictionary:
	return {
		"turn_number": gs.turn_number,
		"current_player_id": gs.current_player_id,
		"current_phase": gs.current_phase,
		"current_sub_phase": gs.current_sub_phase,
		"player_names": gs.player_names.duplicate(),
		"players": [
			GameSerializer.serialize_player_state(gs.players[0], effect_handler),
			GameSerializer.serialize_player_state(gs.players[1], effect_handler),
		],
	}


## Fair-play information hiding: replace the opponent's exact hand/deck order
## with a shuffle of their hidden pool (hand ∪ deck), dealing back the same
## hand count, and shuffle the planner's own deck order (a fair player knows
## their decklist, not their upcoming draws). FULL visibility skips all of it
## (the bot may peek). Consumes the global RNG — call inside the planner's
## RNG fence.
static func determinize(snap: Dictionary, opponent_id: int, visibility: int) -> Dictionary:
	if visibility == BotConfig.InfoVisibility.FULL:
		return snap
	var out := snap.duplicate(true)
	var opp: Dictionary = out["players"][opponent_id]
	var pool: Array = opp["hand"] + opp["main_deck"]
	pool.shuffle()
	var hand_count: int = opp["hand"].size()
	opp["hand"] = pool.slice(0, hand_count)
	opp["main_deck"] = pool.slice(hand_count)
	var own: Dictionary = out["players"][1 - opponent_id]
	own["main_deck"] = own["main_deck"].duplicate()
	own["main_deck"].shuffle()
	return out


func _init(snap: Dictionary, pid: int, config: BotConfig, playstyle: int = BotPlayer.Playstyle.BALANCED) -> void:
	planner_player_id = pid
	var res := {"winner": -1}
	_result = res

	tm = TurnManager.new()
	var rollout_input := KaijuRolloutInput.new()
	tm.player_input = rollout_input # must precede setup_from_save (MatchFactory only creates one if null)
	tm.setup_from_save(snap)
	tm.game_ended.connect(func(winner_id: int, _reason: String) -> void: res["winner"] = winner_id)

	# Throwaway policy bot: answers effect sub-decisions inside the rollout with
	# the same heuristics the live bot uses. Bound to the SCRATCH components,
	# never signal-connected, no scene_tree.
	policy = BotPlayer.new()
	policy.bot_player_id = pid
	policy.config = config
	policy.playstyle = playstyle as BotPlayer.Playstyle
	policy.game_state = tm.game_state
	policy.rules_engine = tm.rules_engine
	policy.turn_manager = tm
	policy.action_handler = tm.action_handler
	policy.effect_handler = tm.effect_handler
	policy.init_combos(true) # combo detection drives planner candidates + evaluator progress
	rollout_input.policy = policy
	rollout_input.planner_player_id = pid


func valid_actions() -> Array:
	return tm.rules_engine.get_valid_actions(tm.game_state)


## Execute one main-phase action on the scratch state (mirrors the
## execute + check-timing + win-check sequence of TurnManager.submit_action).
## Returns false once the rollout game is over.
func apply(action: CardEnums.ActionType, params: Dictionary) -> bool:
	var input := tm.player_input as KaijuRolloutInput
	if input:
		input.decision_log.clear()
	await tm.action_handler.execute(action, params, tm.game_state)
	await tm.action_handler.resolve_check_timing(tm.game_state)
	if tm.is_game_over:
		return false
	return tm.rules_engine.check_win_condition(tm.game_state) < 0


## Sub-decisions the rollout input answered during the last apply() — the
## planner stores these on the plan step so the live bot can replay them.
func decisions() -> Array[Dictionary]:
	var input := tm.player_input as KaijuRolloutInput
	return input.decision_log if input else ([] as Array[Dictionary])


## Play out the turn boundary and a greedy opponent reply on the scratch
## match: our PASS (our counter + end phase), the opponent's start phase,
## their main-phase actions chosen by a throwaway HARD-style greedy bot, and
## their PASS (their counter phase against us) — landing at our next main
## phase, or game over. The whole chain resolves synchronously because every
## engine await goes through KaijuRolloutInput. Returns the number of actions
## consumed (charged against the planner's node budget).
func play_opponent_reply(max_actions: int) -> int:
	var opp_id: int = 1 - planner_player_id
	var opp_policy := BotPlayer.new()
	opp_policy.bot_player_id = opp_id
	opp_policy.config = BotConfig.hard()
	opp_policy.game_state = tm.game_state
	opp_policy.rules_engine = tm.rules_engine
	opp_policy.turn_manager = tm
	opp_policy.action_handler = tm.action_handler
	opp_policy.effect_handler = tm.effect_handler
	var input := tm.player_input as KaijuRolloutInput
	if input:
		input.opponent_policy = opp_policy

	# Rollouts drive actions manually, so the flow machine is still IDLE;
	# arm it so submit_action(PASS) runs the automated phase chain.
	tm.flow_state = TurnManager.FlowState.AWAITING_ACTION
	var used: int = 1
	await tm.submit_action(CardEnums.ActionType.PASS)
	while used < max_actions and not tm.is_game_over \
			and tm.game_state.current_player_id == opp_id \
			and tm.flow_state == TurnManager.FlowState.AWAITING_ACTION:
		var valid: Array = tm.rules_engine.get_valid_actions(tm.game_state)
		var decision: Array = opp_policy._decide_main_action(valid)
		used += 1
		await tm.submit_action(decision[0], decision[1])
	# Cap reached mid-main: close the opponent's turn so their counter phase
	# (the dangerous part for us) is always included in the evaluated state.
	if not tm.is_game_over and tm.game_state.current_player_id == opp_id \
			and tm.flow_state == TurnManager.FlowState.AWAITING_ACTION:
		used += 1
		await tm.submit_action(CardEnums.ActionType.PASS)

	if input:
		input.opponent_policy = null # break the tm -> input -> opp_policy -> tm cycle
	return used


## Winner id if the rollout game ended, -1 otherwise.
func winner() -> int:
	if _result["winner"] >= 0:
		return _result["winner"]
	return tm.rules_engine.check_win_condition(tm.game_state)


func is_over() -> bool:
	return tm.is_game_over or winner() >= 0


func state() -> GameState:
	return tm.game_state


func queries() -> EffectQueries:
	return tm.effect_handler.queries


func rules() -> RulesEngine:
	return tm.rules_engine


func state_hash() -> int:
	return StateCodec.compute_state_hash(tm.game_state)


## Snapshot of the current rollout position (incl. turn-scoped effect state),
## restorable later via KaijuRollout.new — used by the planner to revive beam
## finalists for opponent-reply scoring without keeping rollouts alive.
func capture() -> Dictionary:
	return snapshot(tm.game_state, tm.effect_handler)


## Independent copy of the current rollout position (beam expansion).
func clone() -> KaijuRollout:
	return KaijuRollout.new(capture(), planner_player_id, policy.config, policy.playstyle)


## Break the scratch match's reference cycles. Idempotent; REQUIRED on every
## rollout before dropping it.
func release() -> void:
	if tm == null:
		return
	tm.teardown()
	tm = null
	policy = null
