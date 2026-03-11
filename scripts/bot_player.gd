class_name BotPlayer
extends RefCounted

## AI bot that controls Player 2 in Solo v Bot mode.
## Connects to the same signals as game_board.gd and calls resolve methods directly.

var bot_player_id: int = 1
var action_delay: float = 0.5

var game_state: GameState
var rules_engine: RulesEngine
var turn_manager: TurnManager
var action_handler: ActionHandler
var effect_handler: EffectHandler
var scene_tree: SceneTree


func _delay() -> void:
	if scene_tree and action_delay > 0:
		await scene_tree.create_timer(action_delay).timeout


func is_bot_turn() -> bool:
	return game_state.current_player_id == bot_player_id


# --- Main action decision ---

func _on_awaiting_action(valid_actions: Array) -> void:
	if not is_bot_turn():
		return
	await _delay()
	var action_params := _decide_main_action(valid_actions)
	var action: CardEnums.ActionType = action_params[0]
	var params: Dictionary = action_params[1]
	turn_manager.submit_action(action, params)


func _decide_main_action(valid_actions: Array) -> Array:
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]

	# 1. Win check: zone 7+ and have 2-step invade card and opponent zone 8 empty
	if CardEnums.ActionType.INVADE in valid_actions:
		if player.monster_zone >= 7 and not opponent.zone_has_battle_card(7):
			var invade_idx := _find_best_invade_card(player)
			if invade_idx >= 0:
				return [CardEnums.ActionType.INVADE, {"hand_index": invade_idx}]

	# 2. Play monster if available (increases rage/threat)
	if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
		var playable := rules_engine.get_playable_monsters(player)
		if not playable.is_empty():
			return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": playable[0]}]

	# 3. Play strategy if available
	if CardEnums.ActionType.PLAY_STRATEGY in valid_actions:
		var playable := rules_engine.get_playable_strategy_cards(player)
		if not playable.is_empty():
			return [CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": playable[0]}]

	# 4. Play battle cards using zone priority
	if CardEnums.ActionType.PLAY_BATTLE in valid_actions:
		var result := _decide_battle_play(player, opponent)
		if not result.is_empty():
			return result

	# 5. Gain rage (hand cycling) - discard monster cards
	if CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_cards := rules_engine.get_monster_cards_for_rage(player)
		if not rage_cards.is_empty():
			return [CardEnums.ActionType.GAIN_RAGE, {"hand_index": rage_cards[0]}]

	# 6. Invade based on position
	if CardEnums.ActionType.INVADE in valid_actions:
		var invade_result := _decide_invade(player, opponent)
		if not invade_result.is_empty():
			return invade_result

	# 7. Pass
	return [CardEnums.ActionType.PASS, {}]


func _decide_battle_play(player: PlayerState, opponent: PlayerState) -> Array:
	var playable := rules_engine.get_playable_battle_cards(player, opponent)
	if playable.is_empty():
		return []

	# Pick the first playable battle card and best zone
	for hand_idx in playable:
		var card: Dictionary = player.hand[hand_idx]
		var valid_zones := rules_engine.get_valid_zones_for_card(card, player, opponent)
		if valid_zones.is_empty():
			continue
		var zone := _pick_battle_zone(valid_zones, player, opponent)
		return [CardEnums.ActionType.PLAY_BATTLE, {"hand_index": hand_idx, "zone_index": zone}]
	return []


func _pick_battle_zone(valid_zones: Array[int], player: PlayerState, opponent: PlayerState) -> int:
	# Priority: empty zones first, then zone priority table based on bot's monster zone
	var empty_priority := _get_zone_priority(player.monster_zone)

	# Override: if bot in z1-6 and opponent in z7/z8, prioritize z8
	if player.monster_zone <= 6 and opponent.monster_zone >= 7:
		if 7 in valid_zones and not player.zone_has_cards(7):
			return 7

	# Prefer empty zones in priority order
	for z in empty_priority:
		if z in valid_zones and not player.zone_has_cards(z):
			return z

	# Fallback: any valid zone in priority order
	for z in empty_priority:
		if z in valid_zones:
			return z

	return valid_zones[0]


func _get_zone_priority(monster_zone: int) -> Array[int]:
	# Zone priority table (0-indexed zone indices)
	match monster_zone:
		1: return [7, 6, 5, 4, 3, 2, 1]
		2: return [7, 6, 5, 4, 3, 2, 0]
		3: return [7, 6, 5, 4, 3, 1, 0]
		4: return [7, 6, 5, 4, 2, 1, 0]
		5: return [7, 0, 1, 2, 3, 6, 5]
		6: return [7, 0, 1, 2, 4, 3, 6]
		7: return [0, 1, 2, 5, 4, 3, 7]
		8: return [0, 1, 2, 6, 5, 4, 3]
		_: return [7, 6, 5, 4, 3, 2, 1, 0]


func _find_best_invade_card(player: PlayerState) -> int:
	# Prefer 2-step invasion cards, then 1-step
	var best_idx: int = -1
	var best_icon: int = 0
	for i in range(player.hand.size()):
		var icon: int = player.hand[i].get("invasion_icon", 0)
		if icon > best_icon:
			best_icon = icon
			best_idx = i
	return best_idx


func _decide_invade(player: PlayerState, opponent: PlayerState) -> Array:
	var invade_cards := rules_engine.get_discardable_cards_for_invade(player, opponent)
	if invade_cards.is_empty():
		return []

	var mz := player.monster_zone
	var opp_mz := opponent.monster_zone

	# Zone 6 + have 1-step card → invade to z7 for win setup
	if mz == 6:
		var idx := _find_invade_card_with_steps(player, 1)
		if idx >= 0:
			return [CardEnums.ActionType.INVADE, {"hand_index": idx}]

	# Heavy invade path: z1→z3 (2-step), z3→z4 (1-step), z4→z6 (2-step), z6→z7 (1-step)
	if mz == 1:
		var idx := _find_invade_card_with_steps(player, 2)
		if idx >= 0:
			return [CardEnums.ActionType.INVADE, {"hand_index": idx}]
	elif mz == 3:
		var idx := _find_invade_card_with_steps(player, 1)
		if idx < 0:
			idx = _find_invade_card_with_steps(player, 2)
		if idx >= 0:
			return [CardEnums.ActionType.INVADE, {"hand_index": idx}]
	elif mz == 4:
		var idx := _find_invade_card_with_steps(player, 2)
		if idx >= 0:
			return [CardEnums.ActionType.INVADE, {"hand_index": idx}]

	# Conservative: don't invade from z2 or z5 unless we have a clear path
	# In z7+, invade aggressively
	if mz >= 7:
		var idx := _find_best_invade_card(player)
		if idx >= 0:
			return [CardEnums.ActionType.INVADE, {"hand_index": idx}]

	return []


func _find_invade_card_with_steps(player: PlayerState, steps: int) -> int:
	for i in range(player.hand.size()):
		if player.hand[i].get("invasion_icon", 0) >= steps:
			return i
	return -1


# --- Confirmation ---

func _on_confirmation_requested(_prompt: String, _setting: String) -> void:
	if not is_bot_turn():
		return
	await _delay()
	turn_manager.confirm()


# --- Monster rank-up ---

func _on_monster_rankup_requested(player_id: int, _monsters: Array[Dictionary], valid_indices: Array[int], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick highest valid index (highest rank available)
	var best := valid_indices[valid_indices.size() - 1]
	action_handler.resolve_monster_rankup(best)


# --- Effect choice ---

func _on_choice_requested(player_id: int, options: Array[String], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick first option (can be refined per-card later)
	effect_handler.resolve_choice(0)


# --- Hand discard ---

func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	var player := game_state.players[bot_player_id]
	var indices: Array[int] = _pick_discard_indices(player, discard_count)
	effect_handler.resolve_hand_discard(bot_player_id, indices)


func _pick_discard_indices(player: PlayerState, count: int) -> Array[int]:
	# Prefer discarding monster cards (for cycling), then lowest-value cards
	var monster_indices: Array[int] = []
	var other_indices: Array[int] = []
	for i in range(player.hand.size()):
		if player.hand[i].get("card_type") == CardEnums.CardType.MONSTER:
			monster_indices.append(i)
		else:
			other_indices.append(i)

	var result: Array[int] = []
	# Add monsters first
	for idx in monster_indices:
		if result.size() >= count:
			break
		result.append(idx)
	# Then other cards
	for idx in other_indices:
		if result.size() >= count:
			break
		result.append(idx)
	return result


# --- Deck search ---

func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick first matching card, or empty dict to skip
	if not matching_cards.is_empty():
		effect_handler.resolve_deck_search(matching_cards[0])
	else:
		effect_handler.resolve_deck_search({})


# --- Deck arrange ---

func _on_deck_arrange_requested(player_id: int, cards: Array[Dictionary], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Keep all cards in original order
	effect_handler.resolve_deck_arrange(cards, [])


# --- Card select ---

func _on_card_select_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String, min_count: int, _max_count: int) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick first N matching cards (where N = min_count)
	var selected: Array[Dictionary] = []
	for i in range(mini(min_count, matching_cards.size())):
		selected.append(matching_cards[i])
	effect_handler.resolve_card_select(selected)


# --- Hand card selection ---

func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], _prompt: String, allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_indices.is_empty() and allow_skip:
		effect_handler.resolve_hand_card_selection(-1)
	elif not valid_indices.is_empty():
		effect_handler.resolve_hand_card_selection(valid_indices[0])
	else:
		effect_handler.resolve_hand_card_selection(-1)


# --- Zone target ---

func _on_zone_target_requested(player_id: int, _target_player_id: int, valid_zones: Array[int], _prompt: String, allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_zones.is_empty() and allow_skip:
		effect_handler.resolve_zone_target(-1)
	elif not valid_zones.is_empty():
		# Use zone priority to pick best zone
		var player := game_state.players[bot_player_id]
		var priority := _get_zone_priority(player.monster_zone)
		for z in priority:
			if z in valid_zones:
				effect_handler.resolve_zone_target(z)
				return
		effect_handler.resolve_zone_target(valid_zones[0])
	else:
		effect_handler.resolve_zone_target(-1)


# --- Strategy target ---

func _on_strategy_target_requested(player_id: int, _target_player_id: int, valid_indices: Array[int], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if not valid_indices.is_empty():
		effect_handler.resolve_strategy_target(valid_indices[0])


# --- Cards revealed ---

func _on_cards_revealed_requested(player_id: int, _cards: Array[Dictionary], _title: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	effect_handler.resolve_cards_revealed()
