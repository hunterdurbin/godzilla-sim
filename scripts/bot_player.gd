class_name BotPlayer
extends RefCounted

## AI bot that controls Player 2 in Solo v Bot mode.
## Connects to the same signals as game_board.gd and calls resolve methods directly.

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

enum Playstyle {INVASION, COUNTER, BALANCED}

var bot_player_id: int = 1
var config: BotConfig = BotConfig.normal()
var playstyle: Playstyle = Playstyle.BALANCED

var game_state: GameState
var rules_engine: RulesEngine
var turn_manager: TurnManager
var action_handler: ActionHandler
var effect_handler: EffectHandler
var scene_tree: SceneTree


func analyze_deck() -> void:
	## Scan all cards in the bot's deck + hand to determine playstyle.
	## Call after game setup when deck is populated.
	if config.forced_playstyle >= 0:
		playstyle = config.forced_playstyle as Playstyle
		print("[Bot] Forced playstyle: %s" % Playstyle.keys()[playstyle])
		return

	var player := game_state.players[bot_player_id]
	var all_cards: Array[Dictionary] = []
	all_cards.append_array(player.hand)
	all_cards.append_array(player.main_deck)

	# Count tag occurrences and trigger map signals across all cards
	var invasion_score: float = 0.0
	var counter_score: float = 0.0
	var card_count: int = all_cards.size()
	if card_count == 0:
		return

	# Count monster cards (high monster count suggests aggressive play)
	var monster_count: int = 0
	for card in all_cards:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1

	# Monster ratio contributes to aggressive score (small factor)
	invasion_score += monster_count * 0.5

	for card in all_cards:
		var effect := effect_handler.get_effect(card)
		var tags: Array[String] = []
		if effect:
			tags = effect.get_bot_tags()

		# Tag-based scoring (primary weight)
		if "boosts_threat" in tags:
			invasion_score += 3.0
		if "disrupts_hand" in tags:
			invasion_score += 2.0
		if "destroys_zone" in tags:
			invasion_score += 2.0
		if "advances_monster" in tags:
			invasion_score += 3.0
		if "weakens_opponent" in tags:
			invasion_score += 1.5
		if "mill_opponent" in tags:
			invasion_score += 1.0
		if "column_dependent_monster" in tags:
			invasion_score += 1.0

		if "boosts_cp" in tags:
			counter_score += 3.0
		if "evolves" in tags:
			counter_score += 2.5
		if "evolution" in tags:
			counter_score += 2.0
		if "draws_cards" in tags:
			counter_score += 1.5
		if "searches_deck" in tags:
			counter_score += 1.5
		if "heals_deck" in tags:
			counter_score += 1.5
		if "blocks_invade" in tags:
			counter_score += 2.0
		if "blocks_zone" in tags:
			counter_score += 1.5
		if "column_dependent_battle" in tags:
			counter_score += 1.0

		# Trigger map scoring (secondary weight — half value)
		var script_path: String = card.get("effect_script", "")
		if script_path.is_empty():
			continue
		var triggers: Array = _TriggerMap.TRIGGERS.get(script_path, [])

		if "get_threat_level_modifier" in triggers:
			invasion_score += 1.0
		if "on_when_invading" in triggers:
			invasion_score += 1.5
		if "get_extra_end_phase_advance" in triggers:
			invasion_score += 1.5
		if "on_opponent_rage_changed" in triggers:
			invasion_score += 0.5

		if "get_counter_power_modifier" in triggers or "get_field_cp_modifiers" in triggers \
				or "get_total_cp_modifier" in triggers:
			counter_score += 1.5
		if "get_engagement_restriction" in triggers:
			counter_score += 1.5
		if "get_counter_immunity_threshold" in triggers:
			counter_score += 1.0
		if "prevents_opponent_invasion" in triggers:
			counter_score += 1.5
		if "get_blocked_opponent_zones" in triggers:
			counter_score += 1.0
		if "can_be_destroyed" in triggers or "on_would_be_destroyed" in triggers:
			counter_score += 0.5

	# Determine playstyle from ratio
	var total := invasion_score + counter_score
	if total == 0:
		playstyle = Playstyle.BALANCED
	elif invasion_score / total >= config.playstyle_threshold:
		playstyle = Playstyle.INVASION
	elif counter_score / total >= config.playstyle_threshold:
		playstyle = Playstyle.COUNTER
	else:
		playstyle = Playstyle.BALANCED

	print("[Bot] Deck analysis — invasion: %.1f, counter: %.1f, playstyle: %s" % [
		invasion_score, counter_score, Playstyle.keys()[playstyle]])


func _delay() -> void:
	if scene_tree and config.action_delay > 0:
		await scene_tree.create_timer(config.action_delay).timeout


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
	var near_winning := player.monster_zone >= 6
	var z8_blocked := opponent.zone_has_battle_card(7)
	var cp_gap := _get_cp_gap()  # positive = behind on CP, needs defense
	var needs_defense := cp_gap > 0

	# 1. Play monster if available (increases rage/threat, no downside)
	if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
		var playable := rules_engine.get_playable_monsters(player)
		if not playable.is_empty():
			return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": playable[0]}]

	# 2. Aggressive: INVASION playstyle tries to invade early (skip when behind on CP)
	if not needs_defense and config.use_early_invasion and playstyle == Playstyle.INVASION:
		if CardEnums.ActionType.INVADE in valid_actions:
			# At zone 7+, invade for the win
			if player.monster_zone >= 7 and not z8_blocked:
				var invade_idx := _find_best_invade_card(player)
				if invade_idx >= 0:
					return [CardEnums.ActionType.INVADE, {"hand_index": invade_idx}]
			# At or below threshold, prioritize 2-step invasion to advance quickly
			# At threshold+1, sometimes use 2-step if available
			if player.monster_zone <= config.early_invasion_zone_threshold \
					or (player.monster_zone == config.early_invasion_zone_threshold + 1 \
					and randf() < config.zone_6_two_step_chance):
				var two_step_idx := _find_invade_card_with_steps(player, 2)
				if two_step_idx >= 0:
					var monsters := _count_monster_cards_in_hand(player)
					if not _invasion_blocked_by_rage(player, two_step_idx, monsters):
						return [CardEnums.ActionType.INVADE, {"hand_index": two_step_idx}]

	# 3. When ahead on CP, gain rage early to build threat before playing cards
	if not needs_defense and CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_result := _try_gain_rage(player)
		if not rage_result.is_empty():
			return rage_result

	# 4. Score all playable cards and play the highest-value one
	var best_action := _decide_best_card_play(valid_actions, player, opponent, near_winning, z8_blocked, cp_gap)
	if not best_action.is_empty():
		return best_action

	# 5. Win check: zone 7+ and opponent zone 8 empty → invade to win
	if CardEnums.ActionType.INVADE in valid_actions:
		if player.monster_zone >= 7 and not z8_blocked:
			var win_invade_idx := _find_best_invade_card(player)
			if win_invade_idx >= 0:
				return [CardEnums.ActionType.INVADE, {"hand_index": win_invade_idx}]

	# 6. Gain rage (when behind on CP, rage was skipped earlier — try now as fallback)
	if needs_defense and CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_result := _try_gain_rage(player)
		if not rage_result.is_empty():
			return rage_result

	# 7. Invade based on position and playstyle (skip when behind on CP)
	#    - INVASION: always tries to invade strategically
	#    - BALANCED: invades unless a base strategy is in play (when config allows)
	#    - COUNTER: never invades here (only for the win in step 5)
	if not needs_defense and CardEnums.ActionType.INVADE in valid_actions:
		var try_invade := false
		match playstyle:
			Playstyle.INVASION:
				try_invade = true
			Playstyle.BALANCED:
				try_invade = config.balanced_can_invade \
						and player.monster_zone >= 4 \
						and not _has_base_strategy_in_play(player)

		if try_invade:
			var invade_result := _decide_invade(player, opponent)
			if not invade_result.is_empty():
				return invade_result

	# 8. Pass
	return [CardEnums.ActionType.PASS, {}]


func _try_gain_rage(player: PlayerState) -> Array:
	## Try to gain rage by discarding a monster card. Returns empty array if not possible.
	var rage_cards := rules_engine.get_monster_cards_for_rage(player)
	if rage_cards.is_empty():
		return []

	var safe_rage_cards: Array = []
	if config.protect_two_step_cards:
		var two_step_count := _count_invade_cards_with_steps(player, 2)
		for idx in rage_cards:
			var icon: int = player.hand[idx].get("invasion_icon", 0)
			if icon == 2 and two_step_count <= 1:
				continue
			safe_rage_cards.append(idx)
	else:
		for idx in rage_cards:
			safe_rage_cards.append(idx)

	if safe_rage_cards.is_empty():
		return []

	# Invasion playstyle with only monsters: keep best invasion card, discard worst
	if playstyle == Playstyle.INVASION and _all_hand_cards_are_monsters(player):
		if safe_rage_cards.size() > 1 or _find_best_invade_card(player) < 0:
			var worst_idx := _find_worst_invade_card(safe_rage_cards, player)
			return [CardEnums.ActionType.GAIN_RAGE, {"hand_index": worst_idx}]
		return []

	# Discard the least valuable monster — preserve rank-up matches and high-CP cards
	var worst_idx: int = safe_rage_cards[0]
	var worst_val: int = _card_sort_value(player.hand[worst_idx])
	for i in range(1, safe_rage_cards.size()):
		var idx: int = safe_rage_cards[i]
		var val := _card_sort_value(player.hand[idx])
		if val < worst_val:
			worst_val = val
			worst_idx = idx
	return [CardEnums.ActionType.GAIN_RAGE, {"hand_index": worst_idx}]


func _decide_best_card_play(valid_actions: Array, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool, cp_gap: int = 0) -> Array:
	## Score all playable strategies and battle cards, pick the highest-value one.
	## When cp_gap > 0 (behind on CP), battle cards get a large bonus proportional to their CP.
	var best_score: int = -1
	var best_result: Array = []

	# Score playable strategies
	if CardEnums.ActionType.PLAY_STRATEGY in valid_actions:
		var playable := rules_engine.get_playable_strategy_cards(player)
		for hand_idx in playable:
			var card: Dictionary = player.hand[hand_idx]
			var score := _score_card(card, player, opponent, near_winning, z8_blocked)
			if score > best_score:
				best_score = score
				best_result = [CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx}]

	# Score playable battle cards
	if CardEnums.ActionType.PLAY_BATTLE in valid_actions:
		var battle_playable := rules_engine.get_playable_battle_cards(player, opponent)
		for hand_idx in battle_playable:
			var b_card: Dictionary = player.hand[hand_idx]
			var valid_zones := rules_engine.get_valid_zones_for_card(b_card, player, opponent)
			if valid_zones.is_empty():
				continue
			var b_score := _score_card(b_card, player, opponent, near_winning, z8_blocked)
			# Bonus for base CP value (higher CP cards are more impactful)
			b_score += b_card.get("counter_power", 0) / config.cp_bonus_divisor
			# When behind on CP, strongly prefer high-CP battle cards for defense
			if cp_gap > 0:
				var card_cp: int = b_card.get("counter_power", 0)
				b_score += card_cp / 500  # Large bonus scaled by card's CP
			if b_score > best_score:
				best_score = b_score
				var zone := _pick_battle_zone(valid_zones, player, opponent, b_card)
				best_result = [CardEnums.ActionType.PLAY_BATTLE, {"hand_index": hand_idx, "zone_index": zone}]

	return best_result


func _score_card(card: Dictionary, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool) -> int:
	var score: int = config.base_play_score

	# Score based on trigger map (applies to all cards with effects)
	score += _score_from_triggers(card, opponent)

	var effect := effect_handler.get_effect(card)
	if not effect:
		return score

	var tags: Array[String] = effect.get_bot_tags()
	if tags.is_empty():
		return score

	# Base tag scores from config
	for tag in tags:
		score += config.tag_scores.get(tag, 0)

	# Situational tag bonuses
	for tag in tags:
		if tag in config.tag_situational_bonuses:
			var bonuses: Dictionary = config.tag_situational_bonuses[tag]
			if bonuses.has("near_winning_z8_blocked") and near_winning and z8_blocked:
				score += bonuses["near_winning_z8_blocked"]
			if bonuses.has("opponent_zone_6_plus") and opponent.monster_zone >= 6:
				score += bonuses["opponent_zone_6_plus"]
			if bonuses.has("opponent_zone_5_plus") and opponent.monster_zone >= 5:
				score += bonuses["opponent_zone_5_plus"]
			if bonuses.has("near_winning") and near_winning:
				score += bonuses["near_winning"]

	# Zone/column dependent cards — special logic beyond flat scores
	if "zone_dependent" in tags:
		var preferred: Array[int] = effect.get_bot_preferred_zones()
		for z in preferred:
			if z == player.monster_zone - 1 or z == player.monster_zone:
				score += config.zone_dependent_bonus
				break

	if config.consider_column_tags:
		if "column_dependent_battle" in tags:
			var opp_card_count: int = 0
			for z in range(8):
				if opponent.zone_has_cards(z):
					opp_card_count += 1
			if opp_card_count > 0:
				score += config.column_dependent_battle_base + opp_card_count * config.column_dependent_battle_per_card

		if "column_dependent_monster" in tags:
			var opp_monster_idx: int = opponent.monster_zone - 1
			var opp_column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
			if not opp_column_zones.is_empty():
				score += config.column_dependent_monster_bonus

	# Tag synergies — bonus when this card synergizes with active/deck tags
	if config.enable_synergies:
		score += _score_synergies(tags, player, opponent)

	# Opponent-context bonuses — adjust scores based on opponent's current state
	var opp_hand_size: int = opponent.hand.size()
	var opp_deck_size: int = opponent.main_deck.size()
	var opp_zone_count: int = 0
	for z in range(8):
		if opponent.zone_has_cards(z):
			opp_zone_count += 1
	for tag in tags:
		if tag == "disrupts_hand" and opp_hand_size >= 5:
			score += 15
		elif tag == "mill_opponent" and opp_deck_size <= 15:
			score += 15
		elif tag == "destroys_zone" and opp_zone_count >= 5:
			score += 10
		elif tag == "weakens_opponent" and opponent.rage >= 3:
			score += 10
		elif tag == "boosts_cp" and not _can_counter_opponent():
			score += 15

	# Playstyle multipliers — amplify tags that align with the deck's strategy
	if playstyle == Playstyle.INVASION:
		for tag in tags:
			if tag in ["boosts_threat", "disrupts_hand", "destroys_zone", "advances_monster",
					"weakens_opponent", "mill_opponent", "column_dependent_monster"]:
				score += config.playstyle_multiplier
	elif playstyle == Playstyle.COUNTER:
		for tag in tags:
			if tag in ["boosts_cp", "evolves", "evolution", "draws_cards", "searches_deck",
					"blocks_invade", "blocks_zone", "heals_deck", "column_dependent_battle"]:
				score += config.playstyle_multiplier

	return score


func _score_from_triggers(card: Dictionary, opponent: PlayerState) -> int:
	## Infer a score bonus from the trigger map when bot tags are not defined.
	var script_path: String = card.get("effect_script", "")
	if script_path.is_empty():
		return 0
	var triggers: Array = _TriggerMap.TRIGGERS.get(script_path, [])
	if triggers.is_empty():
		return 0

	var bonus: int = 0

	# Score from trigger rules (grouped triggers — any match adds score once)
	for rule in config.trigger_score_rules:
		var trigger_names: Array = rule[0]
		var rule_score: int = rule[1]
		for t_name in trigger_names:
			if t_name in triggers:
				bonus += rule_score
				break

	# Situational trigger bonuses
	for entry in config.trigger_situational_bonuses:
		var trigger_name: String = entry[0]
		var condition: String = entry[1]
		var sit_bonus: int = entry[2]
		if trigger_name in triggers:
			if condition == "opponent_zone_5_plus" and opponent.monster_zone >= 5:
				bonus += sit_bonus

	return bonus


func _score_synergies(card_tags: Array[String], player: PlayerState, _opponent: PlayerState) -> int:
	## Check if this card's tags synergize with tags on active board cards or in deck/hand.
	if card_tags.is_empty():
		return 0

	# Collect tags from all active board cards (zones + strategies)
	var board_tags: Dictionary = {}
	for z in range(8):
		var zone_card := player.get_zone_top_card(z)
		if zone_card.is_empty():
			continue
		var zone_effect := effect_handler.get_effect(zone_card)
		if zone_effect:
			for tag in zone_effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var sz_effect := effect_handler.get_effect(sz_card)
		if sz_effect:
			for tag in sz_effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1

	# Collect tags from hand (near-future potential)
	var hand_tags: Dictionary = {}
	for h_card in player.hand:
		var h_effect := effect_handler.get_effect(h_card)
		if h_effect:
			for tag in h_effect.get_bot_tags():
				hand_tags[tag] = hand_tags.get(tag, 0) + 1

	# Collect tags from deck (distant potential)
	var deck_tags: Dictionary = {}
	for d_card in player.main_deck:
		var d_effect := effect_handler.get_effect(d_card)
		if d_effect:
			for tag in d_effect.get_bot_tags():
				deck_tags[tag] = deck_tags.get(tag, 0) + 1

	var bonus: int = 0
	for synergy in config.tag_synergies:
		var card_tag: String = synergy[0]
		var synergy_tag: String = synergy[1]
		var synergy_bonus: int = synergy[2]
		if card_tag in card_tags:
			if board_tags.has(synergy_tag):
				bonus += int(synergy_bonus * config.synergy_board_multiplier)
			elif hand_tags.has(synergy_tag):
				bonus += int(synergy_bonus * config.synergy_hand_multiplier)
			elif deck_tags.has(synergy_tag):
				bonus += int(synergy_bonus * config.synergy_deck_multiplier)
	return bonus


func _decide_battle_play(player: PlayerState, opponent: PlayerState) -> Array:
	var playable := rules_engine.get_playable_battle_cards(player, opponent)
	if playable.is_empty():
		return []

	# Pick the first playable battle card and best zone, considering effect tags
	for hand_idx in playable:
		var card: Dictionary = player.hand[hand_idx]
		var valid_zones := rules_engine.get_valid_zones_for_card(card, player, opponent)
		if valid_zones.is_empty():
			continue
		var zone := _pick_battle_zone(valid_zones, player, opponent, card)
		return [CardEnums.ActionType.PLAY_BATTLE, {"hand_index": hand_idx, "zone_index": zone}]
	return []


func _get_crush_zone_indices() -> Array[int]:
	## Returns 0-indexed zone indices the bot's monster will advance through at end of turn.
	var player := game_state.players[bot_player_id]
	var mz := player.monster_zone  # 1-indexed (1-8)
	if mz >= 8:
		return []
	var extra: int = 0
	if effect_handler:
		extra = effect_handler.get_extra_end_phase_advance(bot_player_id)
	var crush_zones: Array[int] = []
	for i in range(1, 2 + extra):
		var zone_num: int = mz + i
		if zone_num > 8:
			break
		crush_zones.append(zone_num - 1)  # Convert to 0-indexed
	return crush_zones


func _get_cp_gap() -> int:
	## Returns opponent threat minus bot CP. Positive = bot is behind, negative/zero = bot is ahead.
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	var total_cp: int = player.get_total_counter_power()
	total_cp += effect_handler.get_counter_power_modifier(player.player_id)
	var threat: int = opponent.get_threat_level()
	threat += effect_handler.get_threat_level_modifier(opponent.player_id)
	return threat - total_cp


func _can_counter_opponent() -> bool:
	## Returns true if the bot's current counter power meets or exceeds the opponent's threat.
	return _get_cp_gap() <= 0


func _pick_battle_zone(valid_zones: Array[int], player: PlayerState, opponent: PlayerState, card: Dictionary = {}) -> int:
	# Crush zone awareness: avoid zones the monster will advance through at end of turn
	var crush_zones := _get_crush_zone_indices()
	if not crush_zones.is_empty():
		var safe_zones: Array[int] = []
		for z in valid_zones:
			if z not in crush_zones:
				safe_zones.append(z)
		if not safe_zones.is_empty():
			valid_zones = safe_zones
		elif _can_counter_opponent():
			# All non-crush zones are occupied — crush zones are expendable since bot can counter.
			# Prefer furthest crush zone (highest index = closest to zone 8).
			crush_zones.sort()
			for i in range(crush_zones.size() - 1, -1, -1):
				var z: int = crush_zones[i]
				if z in valid_zones and not player.zone_has_cards(z):
					return z

	# Check card effect tags for zone preferences
	var effect := effect_handler.get_effect(card) if not card.is_empty() else null
	var tags: Array[String] = []
	if effect:
		tags = effect.get_bot_tags()

	# Zone-dependent: prefer the card's preferred zones
	if "zone_dependent" in tags and effect:
		var preferred: Array[int] = effect.get_bot_preferred_zones()
		# Try preferred empty zones first
		for z in preferred:
			if z in valid_zones and not player.zone_has_cards(z):
				return z
		# Then preferred occupied zones
		for z in preferred:
			if z in valid_zones:
				return z

	# Column-dependent tags — guarded by config
	if config.consider_column_tags:
		# Column-dependent on opponent's monster: must be in same column as opponent's monster
		if "column_dependent_monster" in tags:
			var opp_monster_idx: int = opponent.monster_zone - 1
			if opp_monster_idx >= 0:
				var opp_column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
				# Strongly prefer empty zones in the column
				for z in opp_column_zones:
					if z in valid_zones and not player.zone_has_cards(z):
						return z
				# Accept occupied zones in the column over non-column zones
				for z in opp_column_zones:
					if z in valid_zones:
						return z

		# Column-dependent on own monster: prefer zones in same column as own monster
		if "column_dependent_monster_self" in tags:
			var own_monster_idx: int = player.monster_zone - 1
			if own_monster_idx >= 0:
				var own_column_zones := CardEffect.get_opponent_column_zones(own_monster_idx)
				for z in own_column_zones:
					if z in valid_zones and not player.zone_has_cards(z):
						return z
				for z in own_column_zones:
					if z in valid_zones:
						return z

		# Column-avoid: avoid zones in same column as opponent's battle cards
		if "column_avoid_battle_cards" in tags:
			var avoid_zones: Array[int] = []
			for z in valid_zones:
				if opponent.zone_has_cards(z):
					avoid_zones.append(z)
			var safe_zones: Array[int] = []
			for z in valid_zones:
				if z not in avoid_zones:
					safe_zones.append(z)
			if not safe_zones.is_empty():
				for z in safe_zones:
					if not player.zone_has_cards(z):
						return z
				return safe_zones[0]

		# Column-dependent on opponent's battle cards: prefer zones where opponent has cards
		if "column_dependent_battle" in tags:
			for z in valid_zones:
				if not player.zone_has_cards(z) and opponent.zone_has_cards(z):
					return z

	# Early game: when opponent is in zones 1-4, prioritize placing behind the bot's monster
	# Cards behind the monster are safe from crush and provide defensive CP for counters
	if opponent.monster_zone <= 4 and player.monster_zone > 1:
		var behind_zones: Array[int] = []
		for z in valid_zones:
			if z < player.monster_zone - 1 and not player.zone_has_cards(z):
				behind_zones.append(z)
		if not behind_zones.is_empty():
			# Pick the furthest back zone (lowest index) to spread out defense
			behind_zones.sort()
			return behind_zones[0]

	# No zone priority table — pick random valid zone (prefer empty)
	if not config.use_zone_priority_table:
		var empty_zones: Array[int] = []
		for z in valid_zones:
			if not player.zone_has_cards(z):
				empty_zones.append(z)
		if not empty_zones.is_empty():
			return empty_zones[randi() % empty_zones.size()]
		return valid_zones[randi() % valid_zones.size()]

	# Priority override: if bot in z1-6 and opponent in z7/z8, prioritize z8 first
	if player.monster_zone <= 6 and opponent.monster_zone >= 7:
		if 7 in valid_zones and not player.zone_has_cards(7):
			return 7

	# Build priority considering current zone AND zone+1 (monster advances at end of turn)
	var priority := _get_zone_priority(player.monster_zone)
	var next_zone := mini(player.monster_zone + 1, 8)
	if next_zone != player.monster_zone:
		var next_priority := _get_zone_priority(next_zone)
		# Merge: zones from next_priority that aren't already in priority get appended
		for z in next_priority:
			if z not in priority:
				priority.append(z)

	# Prefer empty zones in priority order
	for z in priority:
		if z in valid_zones and not player.zone_has_cards(z):
			return z

	# Fallback: occupied zones
	if config.overwrite_lowest_cp_when_full:
		# Pick the one with lowest CP card to overwrite
		var lowest_cp: int = 999999
		var lowest_cp_zone: int = valid_zones[0]
		for z in valid_zones:
			var zone_card := player.get_zone_top_card(z)
			var cp: int = zone_card.get("counter_power", 0) if not zone_card.is_empty() else 0
			if cp < lowest_cp:
				lowest_cp = cp
				lowest_cp_zone = z
		return lowest_cp_zone
	else:
		return valid_zones[randi() % valid_zones.size()]


func _get_zone_priority(monster_zone: int) -> Array[int]:
	# Randomly pick one of the listed priority orders per monster zone.
	# Brackets mean "any order" — those sub-arrays get shuffled.
	# Values use 1-based zone numbers, converted to 0-indexed at the end.
	var priority: Array = []
	var shuffled_group: Array = []
	var shuffled_group2: Array = []
	match monster_zone:
		1:
			# z1 => 8,7,6,5,4,3,2 or 7,8,6,5,4,3,2
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5, 4, 3, 2]
			else:
				priority = [7, 8, 6, 5, 4, 3, 2]
		2:
			# z2 => 8,7,6,5,4,3,1 or 7,8,6,5,4,3,1 or 1,8,7,6,5,4,3
			if randi() % 3 == 0:
				priority = [8, 7, 6, 5, 4, 3, 1]
			elif randi() % 2 == 0:
				priority = [7, 8, 6, 5, 4, 3, 1]
			else:
				priority = [1, 8, 7, 6, 5, 4, 3]
		3:
			# z3 => 8,7,6,5,4,[2,1] or 7,8,6,5,4,[2,1]
			shuffled_group = _shuffled([2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5, 4] + shuffled_group
			else:
				priority = [7, 8, 6, 5, 4] + shuffled_group
		4:
			# z4 => 8,7,6,5,[3,2,1] or [1,2,3],8,7,6,5
			shuffled_group = _shuffled([3, 2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5] + shuffled_group
			else:
				priority = shuffled_group + [8, 7, 6, 5]
		5:
			# z5 => 8,[1,2,3],4,7,6 or [1,2,3],8,4,7,6
			shuffled_group = _shuffled([1, 2, 3])
			if randi() % 2 == 0:
				priority = [8] + shuffled_group + [4, 7, 6]
			else:
				priority = shuffled_group + [8, 4, 7, 6]
		6:
			# z6 => 8,[1,2,3,5],4,7 or [1,2,3],[8,4,5],7
			if randi() % 2 == 0:
				shuffled_group = _shuffled([1, 2, 3, 5])
				priority = [8] + shuffled_group + [4, 7]
			else:
				shuffled_group = _shuffled([1, 2, 3])
				shuffled_group2 = _shuffled([8, 4, 5])
				priority = shuffled_group + shuffled_group2 + [7]
		7:
			# z7 => [1,2,3],6,5,4,8
			shuffled_group = _shuffled([1, 2, 3])
			priority = shuffled_group + [6, 5, 4, 8]
		8:
			# z8 => [1,2,3],7,6,5,4
			shuffled_group = _shuffled([1, 2, 3])
			priority = shuffled_group + [7, 6, 5, 4]
		_:
			priority = _shuffled([1, 2, 3, 4, 5, 6, 7, 8])

	# Convert from 1-based zone numbers to 0-indexed
	var result: Array[int] = []
	for z in priority:
		result.append(z - 1)
	return result


func _shuffled(arr: Array) -> Array:
	var copy := arr.duplicate()
	copy.shuffle()
	return copy


func _has_base_strategy_in_play(player: PlayerState) -> bool:
	for sz in player.strategy_zones:
		if not sz.is_empty() and sz.get("is_base", false):
			return true
	return false


func _all_hand_cards_are_monsters(player: PlayerState) -> bool:
	for card in player.hand:
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			return false
	return not player.hand.is_empty()


func _count_monster_cards_in_hand(player: PlayerState) -> int:
	var count: int = 0
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			count += 1
	return count


func _invasion_blocked_by_rage(player: PlayerState, inv_idx: int, monsters_in_hand: int) -> bool:
	# Don't advance to z7/z8 unless bot has enough rage potential (>= 2 monster cards)
	# If already at z7+, always allow (trying to win)
	if player.monster_zone >= 7:
		return false
	var steps: int = player.hand[inv_idx].get("invasion_icon", 1)
	if player.monster_zone + steps >= 7 and monsters_in_hand < 2:
		return true
	return false


func _count_invade_cards_with_steps(player: PlayerState, steps: int) -> int:
	var count: int = 0
	for card in player.hand:
		if card.get("invasion_icon", 0) == steps:
			count += 1
	return count


func _find_worst_invade_card(indices: Array, player: PlayerState) -> int:
	# Find the card with the lowest invasion icon (worst for invading)
	var worst_idx: int = indices[0]
	var worst_icon: int = player.hand[worst_idx].get("invasion_icon", 0)
	for i in indices:
		var icon: int = player.hand[i].get("invasion_icon", 0)
		if icon < worst_icon:
			worst_icon = icon
			worst_idx = i
	return worst_idx


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

	# If opponent is in z7/z8 and bot can't win this turn, don't invade — focus on defense
	if opponent.monster_zone >= 7:
		# Only invade if bot is at z7+ with a path to win past z8
		if mz < 7:
			return []
		if mz == 7 and opponent.zone_has_battle_card(7):
			return [] # z8 blocked, can't win

	# Don't advance to z7/z8 unless bot can expect to gain rage >= 2
	# (rage gain ≈ number of monster cards in hand)
	var monsters_in_hand := _count_monster_cards_in_hand(player)

	var inv_idx: int = -1

	if playstyle == Playstyle.INVASION:
		# Aggressive: invade at any zone, prefer 2-step then any
		inv_idx = _find_invade_card_with_steps(player, 2)
		if inv_idx < 0:
			inv_idx = _find_best_invade_card(player)
		if inv_idx >= 0:
			if not _invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]
	else:
		# Balanced: conservative invade path
		# Zone 6 → z7 for win setup
		if mz == 6:
			inv_idx = _find_invade_card_with_steps(player, 1)
			if inv_idx >= 0 and not _invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]
		# z1→z3 (2-step), z3→z4 (1 or 2-step), z4→z6 (2-step)
		if mz == 1 or mz == 4:
			inv_idx = _find_invade_card_with_steps(player, 2)
		elif mz == 3:
			inv_idx = _find_invade_card_with_steps(player, 1)
			if inv_idx < 0:
				inv_idx = _find_invade_card_with_steps(player, 2)
		# z7+: invade aggressively
		elif mz >= 7:
			inv_idx = _find_best_invade_card(player)
		if inv_idx >= 0:
			if not _invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]

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
	var pick: int
	match config.choice_pick_mode:
		0:
			pick = 0
		1:
			pick = randi() % options.size()
		_:
			pick = _score_choice_options(options)
	effect_handler.resolve_choice(pick)


func _score_choice_options(options: Array[String]) -> int:
	## Score each choice option based on keywords and game state, return best index.
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]

	# Zone selection pattern: "Zone N: CardName" — pick highest CP zone
	if options.size() > 0 and options[0].begins_with("Zone "):
		return _pick_zone_choice(options, opponent)

	var best_idx: int = options.size() - 1  # Default: last option
	var best_score: int = -1

	for i in range(options.size()):
		var opt: String = options[i].to_lower()
		var score: int = 0

		# Destruction — more valuable when opponent has lots of cards on field
		if "destroy" in opt:
			var opp_zone_count: int = 0
			for z in range(8):
				if opponent.zone_has_cards(z):
					opp_zone_count += 1
			score += 20 + opp_zone_count * 3

			# Prefer higher rank thresholds (more targets)
			for rank in [8, 7, 6, 5, 4, 3]:
				if "rank %d" % rank in opt:
					score += rank * 2
					break

			# Prefer destroying more cards
			for count in [3, 2, 1]:
				if "destroy %d" % count in opt or "destroy all" in opt:
					score += count * 5
					break
			if "destroy all" in opt:
				score += 15

			# Zone 8 destruction is high priority when near winning
			if "zone 8" in opt and player.monster_zone >= 6:
				score += 25

		# Hand disruption — better when opponent has many cards
		if "discard" in opt and "opponent" in opt:
			score += 15 + opponent.hand.size() * 2
			# "discard to N" — lower N is stronger
			for n in [1, 2, 3, 4]:
				if "to %d" % n in opt:
					score += (5 - n) * 5
					break

		# Rage increase for bot — good when behind on threat
		if "increase rage" in opt or "rage by" in opt:
			if "opponent" not in opt and "reduce" not in opt:
				score += 15
				if _can_counter_opponent():
					score += 10  # Already ahead on CP, rage builds threat

		# Rage reduction for opponent — good when opponent has high rage
		if "reduce" in opt and ("opponent" in opt or "each" in opt) and "rage" in opt:
			score += 10 + opponent.rage * 3

		# Strategy destruction
		if "destroy" in opt and "strategy" in opt:
			var has_strategies := false
			for sz in opponent.strategy_zones:
				if not sz.is_empty():
					has_strategies = true
					break
			if has_strategies:
				score += 25

		# Mill self — useful if deck has plays_from_discard synergy
		if "your deck" in opt and "discard" in opt:
			score += 5  # Low priority unless synergy-driven

		# Return monster — generally good
		if "return" in opt and "monster" in opt:
			score += 20
			if "any monster" in opt:
				score += 10  # Broader target = better

		if score > best_score:
			best_score = score
			best_idx = i

	return best_idx


func _pick_zone_choice(options: Array[String], opponent: PlayerState) -> int:
	## For "Zone N: CardName" options, pick the zone with highest CP card.
	var best_idx: int = 0
	var best_cp: int = -1
	for i in range(options.size()):
		var opt: String = options[i]
		# Parse zone number from "Zone N: ..."
		var zone_str := opt.substr(5, opt.find(":") - 5).strip_edges()
		if not zone_str.is_valid_int():
			continue
		var zone_num: int = zone_str.to_int()
		var zone_idx: int = zone_num - 1
		if zone_idx < 0 or zone_idx >= 8:
			continue
		var zone_card := opponent.get_zone_top_card(zone_idx)
		var cp: int = zone_card.get("counter_power", 0) if not zone_card.is_empty() else 0
		if cp > best_cp:
			best_cp = cp
			best_idx = i
	return best_idx


# --- Hand discard ---

func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	var player := game_state.players[bot_player_id]
	var indices: Array[int] = _pick_discard_indices(player, discard_count)
	effect_handler.resolve_hand_discard(bot_player_id, indices)


func _pick_discard_indices(player: PlayerState, count: int) -> Array[int]:
	## Priority: monster cards first, then non-playable cards, then random.
	var opponent := game_state.players[1 - bot_player_id]
	var monster_indices: Array[int] = []
	var non_playable_indices: Array[int] = []
	var playable_indices: Array[int] = []

	# Categorize hand cards
	var playable_battles := rules_engine.get_playable_battle_cards(player, opponent)
	var playable_strategies := rules_engine.get_playable_strategy_cards(player)
	var playable_set: Dictionary = {}
	for idx in playable_battles:
		playable_set[idx] = true
	for idx in playable_strategies:
		playable_set[idx] = true

	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_indices.append(i)
		elif not playable_set.has(i):
			non_playable_indices.append(i)
		else:
			playable_indices.append(i)

	# Sort monsters by value ascending — discard least valuable first (preserve rank-up matches)
	monster_indices.sort_custom(func(a: int, b: int) -> bool:
		return _card_sort_value(player.hand[a]) < _card_sort_value(player.hand[b]))

	var pools: Dictionary = {
		"monsters": monster_indices,
		"non_playable": non_playable_indices,
		"playable": playable_indices,
	}

	var result: Array[int] = []
	for pool_name in config.discard_priority:
		var pool: Array = pools.get(pool_name, [])
		if pool_name == "playable":
			pool.shuffle()
		for idx in pool:
			if result.size() >= count:
				break
			result.append(idx)
	return result


# --- Deck search ---

func _pick_evolution_card(candidates: Array[Dictionary]) -> Dictionary:
	## Pick an evolution candidate. When config requires CP upgrade, only pick
	## candidates with >= CP than the card being evolved. Prefer highest rank, then CP.
	## Skips evolution if the current card's effect is more valuable than the best candidate.
	if candidates.is_empty():
		return {}

	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]

	# Find the zone card being evolved
	var current_card: Dictionary = {}
	for z in range(8):
		var zone_card := player.get_zone_top_card(z)
		if not zone_card.is_empty() and zone_card.get("evolution_rank", -1) >= 0:
			current_card = zone_card
			break

	# Filter out candidates that are the same card as the current one
	var current_id: String = current_card.get("id", "")
	var filtered: Array[Dictionary] = []
	for card in candidates:
		if card.get("id", "") != current_id or current_id.is_empty():
			filtered.append(card)
	if filtered.is_empty():
		return {}  # Only option is the same card — skip evolution

	var valid: Array[Dictionary] = []
	if config.evolution_require_cp_upgrade:
		var current_cp: int = current_card.get("counter_power", 0)
		for card in filtered:
			if card.get("counter_power", 0) >= current_cp:
				valid.append(card)
		if valid.is_empty():
			return {}
	else:
		valid.assign(filtered)

	# Sort: highest rank first, then highest CP
	valid.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = a.get("rank", 0)
		var rank_b: int = b.get("rank", 0)
		if rank_a != rank_b:
			return rank_a > rank_b
		return a.get("counter_power", 0) > b.get("counter_power", 0)
	)

	var best_candidate: Dictionary = valid[0]

	# Compare current card's effect value vs best candidate's effect value
	# Skip evolution if current card's effect is significantly more valuable
	if not current_card.is_empty() and effect_handler:
		var current_score := _score_from_triggers(current_card, opponent)
		var candidate_score := _score_from_triggers(best_candidate, opponent)
		# Also factor in bot tags
		var current_effect := effect_handler.get_effect(current_card)
		var candidate_effect := effect_handler.get_effect(best_candidate)
		if current_effect:
			for tag in current_effect.get_bot_tags():
				current_score += config.tag_scores.get(tag, 0)
		if candidate_effect:
			for tag in candidate_effect.get_bot_tags():
				candidate_score += config.tag_scores.get(tag, 0)
		# Skip if current effect is worth 20+ more than candidate
		if current_score > candidate_score + 20:
			return {}

	return best_candidate


func _card_sort_value(card: Dictionary) -> int:
	## Score a card for selection priority: highest CP/threat first, then lowest rank.
	## Higher return value = better pick.
	var cp: int = card.get("counter_power", 0)
	var threat: int = card.get("threat_level", 0)
	var rank: int = card.get("rank", 0)
	# Primary: highest CP or threat (whichever is larger)
	# Secondary: lowest rank (subtract rank so lower rank scores higher)
	var base := maxi(cp, threat) * 10 - rank

	# Monster cards that match the bot's active monster get a big bonus
	if card.get("card_type") == CardEnums.CardType.MONSTER:
		var player := game_state.players[bot_player_id]
		var active := player.current_monster
		if not active.is_empty():
			var active_rank: int = active.get("rank", 0)
			var active_traits: Array = active.get("traits", [])
			var card_rank: int = card.get("rank", 0)
			var card_traits: Array = card.get("traits", [])
			# Burst rank matching active rank is highest priority
			var has_burst_match := false
			if effect_handler != null:
				var effect := effect_handler.get_effect(card)
				if effect != null and effect.get_burst_rank() == active_rank:
					has_burst_match = true
					base += config.monster_burst_match_bonus
			# Same rank as active monster is next best for rank-up
			if not has_burst_match and card_rank == active_rank:
				base += config.monster_rank_match_bonus
			# Shared traits indicate same monster line
			for t in card_traits:
				if t in active_traits:
					base += config.monster_trait_bonus
					break
	return base


func _pick_best_card(cards: Array[Dictionary]) -> Dictionary:
	## Pick the best card from a list using _card_sort_value.
	if cards.is_empty():
		return {}
	var best: Dictionary = cards[0]
	var best_val: int = _card_sort_value(best)
	for i in range(1, cards.size()):
		var val := _card_sort_value(cards[i])
		if val > best_val:
			best_val = val
			best = cards[i]
	return best


func _sort_cards_by_value(cards: Array[Dictionary]) -> Array[Dictionary]:
	## Sort cards by _card_sort_value descending (best first).
	var sorted: Array[Dictionary] = cards.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _card_sort_value(a) > _card_sort_value(b))
	return sorted


func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()

	var selected: Dictionary
	# Evolution search: only evolve if a candidate has >= CP, prefer highest rank
	if "evolve" in prompt.to_lower():
		selected = _pick_evolution_card(matching_cards)
	else:
		# Default: pick best matching card by CP/threat then lowest rank
		selected = _pick_best_card(matching_cards)
	effect_handler.resolve_deck_search(selected)


# --- Deck arrange ---

func _on_deck_arrange_requested(player_id: int, cards: Array[Dictionary], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()

	var player := game_state.players[bot_player_id]
	var active := player.current_monster
	var active_rank: int = active.get("rank", 0) if not active.is_empty() else -1
	var active_traits: Array = active.get("traits", []) if not active.is_empty() else []

	var keep: Array[Dictionary] = []
	var discard: Array[Dictionary] = []

	for card in cards:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			# Keep monsters that match active monster (rank-up / burst potential)
			var dominated := true
			if not active.is_empty():
				var card_rank: int = card.get("rank", 0)
				var card_traits: Array = card.get("traits", [])
				if card_rank == active_rank:
					dominated = false  # Same rank = rank-up candidate
				for t in card_traits:
					if t in active_traits:
						dominated = false  # Shared trait = same monster line
						break
				if card.get("invasion_icon", 0) > 0:
					dominated = false  # Has invasion value
				if effect_handler:
					var effect := effect_handler.get_effect(card)
					if effect and effect.get_burst_rank() == active_rank:
						dominated = false  # Burst rank match
			else:
				dominated = false  # No active monster, keep everything
			if dominated:
				discard.append(card)
			else:
				keep.append(card)
		else:
			keep.append(card)

	# Sort kept cards: best on top (first drawn)
	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _card_sort_value(a) > _card_sort_value(b))

	effect_handler.resolve_deck_arrange(keep, discard)


# --- Card select ---

func _on_card_select_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String, min_count: int, _max_count: int) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick best N matching cards sorted by CP/threat then lowest rank
	var sorted := _sort_cards_by_value(matching_cards)
	var selected: Array[Dictionary] = []
	for i in range(mini(min_count, sorted.size())):
		selected.append(sorted[i])
	effect_handler.resolve_card_select(selected)


# --- Hand card selection ---

func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], _prompt: String, allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_indices.is_empty():
		effect_handler.resolve_hand_card_selection(-1)
		return
	# Pick the hand card with highest CP/threat, lowest rank
	var player := game_state.players[bot_player_id]
	var best_idx: int = valid_indices[0]
	var best_val: int = _card_sort_value(player.hand[best_idx])
	for i in range(1, valid_indices.size()):
		var idx: int = valid_indices[i]
		var val := _card_sort_value(player.hand[idx])
		if val > best_val:
			best_val = val
			best_idx = idx
	effect_handler.resolve_hand_card_selection(best_idx)


# --- Zone target ---

func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], _prompt: String, allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_zones.is_empty() and allow_skip:
		effect_handler.resolve_zone_target(-1)
	elif not valid_zones.is_empty():
		var player := game_state.players[bot_player_id]
		var opponent := game_state.players[1 - bot_player_id]

		if target_player_id != bot_player_id:
			# Targeting opponent's zones — pick strategically
			effect_handler.resolve_zone_target(_pick_opponent_zone_target(valid_zones, player, opponent))
		else:
			# Targeting own zones — use existing priority logic
			effect_handler.resolve_zone_target(_pick_own_zone_target(valid_zones, player))
	else:
		effect_handler.resolve_zone_target(-1)


func _pick_opponent_zone_target(valid_zones: Array[int], player: PlayerState, opponent: PlayerState) -> int:
	## Pick the best opponent zone to destroy/target.
	var mz := player.monster_zone
	var can_win := mz == 8 or (mz == 7 and _find_invade_card_with_steps(player, 2) >= 0)

	# Near win: clear the invasion path first (z8, then z7)
	if can_win:
		for z in config.destroy_zone_priority_near_win:
			if z in valid_zones:
				return z

	# Priority 1: zone 8 if it's blocking invasion and bot is in z6+
	if mz >= 6 and 7 in valid_zones and opponent.zone_has_cards(7):
		return 7

	# Priority 2: destroy the opponent's highest-CP card to weaken their counter
	var cp_modifiers := effect_handler.get_zone_cp_modifiers(opponent.player_id)
	var best_zone: int = valid_zones[0]
	var best_cp: int = -1
	for z in valid_zones:
		var zone_card := opponent.get_zone_top_card(z)
		if zone_card.is_empty():
			continue
		var cp: int = zone_card.get("counter_power", 0) + cp_modifiers[z]
		if cp > best_cp:
			best_cp = cp
			best_zone = z

	# If all valid zones are empty, pick one in the bot's invasion path
	if best_cp < 0:
		# Prefer zones the bot's monster will pass through
		for z_num in range(mz + 1, 9):
			if (z_num - 1) in valid_zones:
				return z_num - 1
		return valid_zones[0]

	return best_zone


func _pick_own_zone_target(valid_zones: Array[int], player: PlayerState) -> int:
	## Pick one of the bot's own zones (for placement, movement, etc.)
	var mz := player.monster_zone
	var priority := _get_zone_priority(mz)
	for z in priority:
		if z in valid_zones:
			return z
	return valid_zones[0]


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
