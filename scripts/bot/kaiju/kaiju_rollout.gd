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
## rehydrated to independent dicts on restore.
static func snapshot(gs: GameState) -> Dictionary:
	return {
		"turn_number": gs.turn_number,
		"current_player_id": gs.current_player_id,
		"current_phase": gs.current_phase,
		"current_sub_phase": gs.current_sub_phase,
		"player_names": gs.player_names.duplicate(),
		"players": [
			GameSerializer.serialize_player_state(gs.players[0]),
			GameSerializer.serialize_player_state(gs.players[1]),
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
	rollout_input.policy = policy
	rollout_input.planner_player_id = pid


func valid_actions() -> Array:
	return tm.rules_engine.get_valid_actions(tm.game_state)


## Execute one main-phase action on the scratch state (mirrors the
## execute + check-timing + win-check sequence of TurnManager.submit_action).
## Returns false once the rollout game is over.
func apply(action: CardEnums.ActionType, params: Dictionary) -> bool:
	await tm.action_handler.execute(action, params, tm.game_state)
	await tm.action_handler.resolve_check_timing(tm.game_state)
	if tm.is_game_over:
		return false
	return tm.rules_engine.check_win_condition(tm.game_state) < 0


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


## Independent copy of the current rollout position (beam expansion).
func clone() -> KaijuRollout:
	return KaijuRollout.new(snapshot(tm.game_state), planner_player_id, policy.config, policy.playstyle)


## Break the scratch match's reference cycles. Idempotent; REQUIRED on every
## rollout before dropping it.
func release() -> void:
	if tm == null:
		return
	tm.teardown()
	tm = null
	policy = null
