class_name KaijuRolloutInput
extends PlayerInput

## Synchronous PlayerInput for KAIJU rollouts. Engine coroutines that `await`
## these methods complete in the same call stack — no frames, no signals.
##
## Decisions for the planner's player delegate to the scratch policy
## BotPlayer's heuristics (the same scorers the live bot's _on_* handlers
## use), so rollout sub-decisions match what the real bot would do when the
## plan is executed. Decisions for the other player fall back to the base
## PlayerInput defaults (deterministic auto-picks).
##
## Signatures must stay byte-identical to PlayerInput: a typed-array mismatch
## on a dynamically awaited call aborts the engine coroutine silently.

var policy: BotPlayer = null
var planner_player_id: int = 0


func teardown() -> void:
	policy = null


func choose_option(player_id: int, options: Array[String], prompt: String) -> int:
	if player_id != planner_player_id or policy == null:
		return super(player_id, options, prompt)
	return policy._score_choice_options(options)


func search_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool) -> Dictionary:
	if player_id != planner_player_id or policy == null:
		return super(player_id, matching, all_cards, prompt, allow_skip)
	if "evolve" in prompt.to_lower():
		return policy._pick_evolution_card(matching)
	return policy._pick_best_card(matching)


func select_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> Array[Dictionary]:
	if player_id != planner_player_id or policy == null:
		return super(player_id, matching, all_cards, prompt, min_count, max_count)
	var sorted := policy._sort_cards_by_value(matching)
	var selected: Array[Dictionary] = []
	for i in range(mini(min_count, sorted.size())):
		selected.append(sorted[i])
	return selected


func choose_hand_discards(player_id: int, count: int, hand_size: int) -> Array[int]:
	if player_id != planner_player_id or policy == null:
		return super(player_id, count, hand_size)
	return policy._pick_discard_indices(policy.game_state.players[planner_player_id], count)


func select_hand_card(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> int:
	if player_id != planner_player_id or policy == null:
		return super(player_id, valid_indices, prompt, allow_skip)
	if valid_indices.is_empty():
		return -1
	var player: PlayerState = policy.game_state.players[planner_player_id]
	# Mirror the live handler: protect the last 2-step invasion card, then
	# pick the highest-value hand card.
	var safe: Array[int] = []
	for idx in valid_indices:
		if not policy._is_last_two_step_card(player, idx):
			safe.append(idx)
	var pick_from: Array[int] = safe if not safe.is_empty() else valid_indices
	var best_idx: int = pick_from[0]
	var best_val: int = policy._card_sort_value(player.hand[best_idx])
	for i in range(1, pick_from.size()):
		var val := policy._card_sort_value(player.hand[pick_from[i]])
		if val > best_val:
			best_val = val
			best_idx = pick_from[i]
	return best_idx


func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
	if player_id != planner_player_id or policy == null or valid_zones.is_empty():
		return super(player_id, target_player_id, valid_zones, prompt, allow_skip)
	var player: PlayerState = policy.game_state.players[planner_player_id]
	var opponent: PlayerState = policy.game_state.players[1 - planner_player_id]
	var pick: int
	if target_player_id == planner_player_id:
		pick = policy._pick_own_zone_target(valid_zones, player)
	else:
		pick = policy._pick_opponent_zone_target(valid_zones, player, opponent)
	return pick if pick in valid_zones else valid_zones[0]


func select_zones(player_id: int, target_player_id: int, valid_zones: Array[int], count: int, up_to: bool, prompt: String) -> Array[int]:
	if player_id != planner_player_id or policy == null:
		return super(player_id, target_player_id, valid_zones, count, up_to, prompt)
	# Mirror the live handler: greedy repeated best-pick up to count.
	var player: PlayerState = policy.game_state.players[planner_player_id]
	var opponent: PlayerState = policy.game_state.players[1 - planner_player_id]
	var remaining: Array[int] = valid_zones.duplicate()
	var picked: Array[int] = []
	while picked.size() < count and not remaining.is_empty():
		var pick: int
		if target_player_id == planner_player_id:
			pick = policy._pick_own_zone_target(remaining, player)
		else:
			pick = policy._pick_opponent_zone_target(remaining, player, opponent)
		if pick not in remaining:
			pick = remaining[0]
		picked.append(pick)
		remaining.erase(pick)
	return picked


func choose_rankup(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> int:
	if player_id != planner_player_id or policy == null:
		return super(player_id, monsters, valid_indices, prompt)
	return policy._score_rankup_candidates(monsters, valid_indices)


func arrange_deck(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	if player_id != planner_player_id or policy == null:
		return super(player_id, cards, prompt)
	return policy._plan_deck_arrange(cards)
