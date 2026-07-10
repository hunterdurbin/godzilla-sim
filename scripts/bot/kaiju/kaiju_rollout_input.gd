class_name KaijuRolloutInput
extends PlayerInput

## Synchronous PlayerInput for KAIJU rollouts. Engine coroutines that `await`
## these methods complete in the same call stack — no frames, no signals.
##
## Decisions for the planner's player delegate to the scratch policy
## BotPlayer's heuristics (the same scorers the live bot's _on_* handlers
## use), so rollout sub-decisions match what the real bot would do when the
## plan is executed. Decisions for the other player fall back to the base
## PlayerInput defaults — unless the opponent-reply ply is active
## (`opponent_policy` set by KaijuRollout.play_opponent_reply), in which case
## they use the same heuristics on the opponent's throwaway bot.
##
## Every planner-side answer is also recorded into `decision_log` (cleared by
## KaijuRollout.apply per action) so the planner can store the winning line's
## sub-decisions on each plan step and the live bot can replay them verbatim
## instead of re-deriving heuristically (see BotPlayer._pop_scripted).
## Card picks are recorded as instance ids — snapshot round-trips ids, so the
## same ids exist in the live game.
##
## Signatures must stay byte-identical to PlayerInput: a typed-array mismatch
## on a dynamically awaited call aborts the engine coroutine silently.

var policy: BotPlayer = null
var planner_player_id: int = 0

# Throwaway greedy bot answering the OPPONENT's decisions while the
# opponent-reply ply runs; null during normal plan-step rollouts.
var opponent_policy: BotPlayer = null

# Sub-decisions made for the planner's player during the current apply();
# entries are {"m": kind, "v": value} consumed by BotPlayer._pop_scripted.
var decision_log: Array[Dictionary] = []


func teardown() -> void:
	policy = null
	opponent_policy = null
	decision_log.clear()


## The heuristic bot answering for `player_id`, or null to use base defaults.
func _bot_for(player_id: int) -> BotPlayer:
	if player_id == planner_player_id:
		return policy
	return opponent_policy


func _record(player_id: int, kind: String, value: Variant) -> void:
	# Only the planner's own answers become plan sub-decisions.
	if player_id == planner_player_id:
		decision_log.append({"m": kind, "v": value})


static func _card_ids(cards: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for card in cards:
		ids.append(str(card.get("id", "")))
	return ids


func choose_option(player_id: int, options: Array[String], prompt: String) -> int:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, options, prompt)
	var pick: int = bot._score_choice_options(options)
	_record(player_id, "choice", pick)
	return pick


func search_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool) -> Dictionary:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, matching, all_cards, prompt, allow_skip)
	var selected: Dictionary
	if "evolve" in prompt.to_lower():
		selected = bot._pick_evolution_card(matching)
	else:
		selected = bot._pick_best_card(matching)
	_record(player_id, "deck_search", str(selected.get("id", "")))
	return selected


func select_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> Array[Dictionary]:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, matching, all_cards, prompt, min_count, max_count)
	var sorted := bot._sort_cards_by_value(matching)
	var selected: Array[Dictionary] = []
	for i in range(mini(min_count, sorted.size())):
		selected.append(sorted[i])
	_record(player_id, "card_select", _card_ids(selected))
	return selected


func choose_hand_discards(player_id: int, count: int, hand_size: int) -> Array[int]:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, count, hand_size)
	var indices: Array[int] = bot._pick_discard_indices(bot.game_state.players[bot.bot_player_id], count)
	_record(player_id, "hand_discard", indices)
	return indices


func select_hand_card(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> int:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, valid_indices, prompt, allow_skip)
	if valid_indices.is_empty():
		return -1 # no record: the live handler resolves -1 without a queue pop
	var player: PlayerState = bot.game_state.players[bot.bot_player_id]
	# Mirror the live handler: protect the last 2-step invasion card, then
	# pick the highest-value hand card.
	var safe: Array[int] = []
	for idx in valid_indices:
		if not bot._is_last_two_step_card(player, idx):
			safe.append(idx)
	var pick_from: Array[int] = safe if not safe.is_empty() else valid_indices
	var best_idx: int = pick_from[0]
	var best_val: int = bot._card_sort_value(player.hand[best_idx])
	for i in range(1, pick_from.size()):
		var val := bot._card_sort_value(player.hand[pick_from[i]])
		if val > best_val:
			best_val = val
			best_idx = pick_from[i]
	_record(player_id, "hand_card", best_idx)
	return best_idx


func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
	var bot := _bot_for(player_id)
	if bot == null or valid_zones.is_empty():
		return super(player_id, target_player_id, valid_zones, prompt, allow_skip)
	var player: PlayerState = bot.game_state.players[bot.bot_player_id]
	var opponent: PlayerState = bot.game_state.players[1 - bot.bot_player_id]
	var pick: int
	if target_player_id == bot.bot_player_id:
		pick = bot._pick_own_zone_target(valid_zones, player)
	else:
		pick = bot._pick_opponent_zone_target(valid_zones, player, opponent)
	if pick not in valid_zones:
		pick = valid_zones[0]
	_record(player_id, "zone", pick)
	return pick


func select_zones(player_id: int, target_player_id: int, valid_zones: Array[int], count: int, up_to: bool, prompt: String) -> Array[int]:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, target_player_id, valid_zones, count, up_to, prompt)
	# Mirror the live handler: greedy repeated best-pick up to count.
	var player: PlayerState = bot.game_state.players[bot.bot_player_id]
	var opponent: PlayerState = bot.game_state.players[1 - bot.bot_player_id]
	var remaining: Array[int] = valid_zones.duplicate()
	var picked: Array[int] = []
	while picked.size() < count and not remaining.is_empty():
		var pick: int
		if target_player_id == bot.bot_player_id:
			pick = bot._pick_own_zone_target(remaining, player)
		else:
			pick = bot._pick_opponent_zone_target(remaining, player, opponent)
		if pick not in remaining:
			pick = remaining[0]
		picked.append(pick)
		remaining.erase(pick)
	_record(player_id, "zones", picked)
	return picked


func select_strategy(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	if player_id != planner_player_id:
		return super(player_id, target_player_id, valid_indices, prompt)
	# Mirror the live handler (valid_indices[0]) and record it so the scripted
	# replay queue stays sequence-aligned with the rollout.
	var pick: int = valid_indices[0] if not valid_indices.is_empty() else -1
	_record(player_id, "strategy", pick)
	return pick


func choose_rankup(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> int:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, monsters, valid_indices, prompt)
	var pick: int = bot._score_rankup_candidates(monsters, valid_indices)
	_record(player_id, "rankup", pick)
	return pick


func arrange_deck(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	var bot := _bot_for(player_id)
	if bot == null:
		return super(player_id, cards, prompt)
	var plan: Dictionary = bot._plan_deck_arrange(cards)
	_record(player_id, "deck_arrange", {
		"keep": _card_ids(plan["keep"]),
		"discard": _card_ids(plan["discard"]),
	})
	return plan
