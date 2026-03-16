class_name BotPlayer
extends RefCounted

## AI bot that controls Player 2 in Solo v Bot mode.
## Connects to the same signals as game_board.gd and calls resolve methods directly.

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

const _TRIGGER_FULFILL_MAP: Dictionary = {
	"on_enter": &"bot_can_fulfill_on_enter",
	"on_when_invading": &"bot_can_fulfill_on_when_invading",
	"on_revenge": &"bot_can_fulfill_on_revenge",
	"on_crush": &"bot_can_fulfill_on_crush",
	"on_discard_from_hand": &"bot_can_fulfill_on_discard_from_hand",
	"on_burst_discard": &"bot_can_fulfill_on_burst_discard",
	"on_rage_changed": &"bot_can_fulfill_on_rage_changed",
	"on_opponent_rage_changed": &"bot_can_fulfill_on_opponent_rage_changed",
	"on_monster_advance": &"bot_can_fulfill_on_monster_advance",
	"on_phase_start": &"bot_can_fulfill_on_phase_start",
	"on_monster_played": &"bot_can_fulfill_on_monster_played",
	"get_counter_power_modifier": &"bot_can_fulfill_counter_power",
	"get_field_cp_modifiers": &"bot_can_fulfill_field_cp",
	"get_total_cp_modifier": &"bot_can_fulfill_total_cp",
	"get_threat_level_modifier": &"bot_can_fulfill_threat_level",
	"on_counter_success": &"bot_can_fulfill_counter_success",
}

enum Playstyle {INVASION, COUNTER, BALANCED}

var bot_player_id: int = 1
var config: BotConfig = BotConfig.normal()
var playstyle: Playstyle = Playstyle.BALANCED

# Shin combo plan: set per action decision, cleared when combo is not viable.
# Keys: "state" ("full"|"partial"), "viability" (int, full only),
#        "advance_to_6_idx" (-1 if zone 6+), "advancement_idx" (card #2),
#        "advancement_is_monster" (bool), "destroy_idx" (-1 if z8 clear),
#        "invade_idx" (2-invasion card)
var _shin_combo_plan: Dictionary = {}

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
		if "advances_self" in tags:
			invasion_score += 3.0
		if "advances_opponent" in tags:
			invasion_score += 2.0
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

	# 0. Shin combo check — detect multi-turn win path (hard mode only)
	_shin_combo_plan = {}
	if config.use_shin_combo_check:
		_shin_combo_plan = _check_shin_combo(player, opponent)
		if not _shin_combo_plan.is_empty():
			print("[Bot] Shin combo detected! state=%s viability=%d plan=%s" % [
				_shin_combo_plan.get("state", "?"),
				_shin_combo_plan.get("viability", 0),
				str(_shin_combo_plan)])

	var _shin_is_full: bool = _shin_combo_plan.get("state") == "full"

	# Downgrade full → partial if advancement monster exists but isn't playable yet.
	# Pieces stay protected but scoring doesn't boost cards for a combo that can't fire.
	if _shin_is_full and _shin_combo_plan.get("advancement_is_monster", false):
		var adv_idx: int = _shin_combo_plan.get("advancement_idx", -1)
		if adv_idx >= 0 and _shin_combo_plan.get("advance_to_6_idx", -1) < 0:
			# At zone 6+: check if advancement monster is actually playable
			var playable := rules_engine.get_playable_monsters(player)
			if adv_idx not in playable:
				_shin_is_full = false

	# 1. Play monster if available (increases rage/threat, no downside)
	#    When shin combo is "full" and card #2 is a monster rank-up:
	#    - Before zone 6: skip monster play (advance card #1 must go first)
	#    - At zone 6+: play ONLY the advancement monster, skip all others
	#    When combo is "partial" or "full": never play the advancement monster
	#    as a normal rank-up — it must be saved for the combo.
	if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
		var skip_monster := false
		var shin_adv_idx: int = -1
		if _shin_combo_plan.get("advancement_is_monster", false):
			shin_adv_idx = _shin_combo_plan.get("advancement_idx", -1)
		if _shin_is_full and shin_adv_idx >= 0:
			if _shin_combo_plan.get("advance_to_6_idx", -1) >= 0:
				# Card #1 not played yet — skip all monster plays
				skip_monster = true
			else:
				# At zone 6+: play the advancement monster if it's ready
				var playable := rules_engine.get_playable_monsters(player)
				if shin_adv_idx in playable:
					return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": shin_adv_idx}]
				# Not playable yet (trait mismatch or wrong rank) — allow other
				# monsters normally. Playing monsters builds rage/threat and the
				# rank-up chain may eventually make the advancement monster playable.
		if not skip_monster:
			var playable := rules_engine.get_playable_monsters(player)
			# Exclude the advancement monster from normal plays (full or partial)
			if shin_adv_idx >= 0:
				playable = playable.filter(func(idx: int) -> bool: return idx != shin_adv_idx)
			if not playable.is_empty():
				return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": playable[0]}]

	# 2. Aggressive: INVASION playstyle tries to invade early
	#    When shin combo is active (full or partial), don't burn the reserved 2-step card.
	if config.use_early_invasion and playstyle == Playstyle.INVASION:
		if CardEnums.ActionType.INVADE in valid_actions:
			# At zone 7+, invade for the win
			if player.monster_zone >= 7 and not z8_blocked:
				var invade_idx := _find_best_invade_card(player)
				if invade_idx >= 0:
					return [CardEnums.ActionType.INVADE, {"hand_index": invade_idx}]
			# At or below threshold, prioritize 2-step invasion to advance quickly
			if _shin_combo_plan.is_empty():
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
	#    When shin combo is active, skip to preserve the reserved 2-step card.
	if not needs_defense and CardEnums.ActionType.INVADE in valid_actions \
			and _shin_combo_plan.is_empty():
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
	var shin_reserved := _get_shin_combo_reserved_indices()
	if config.protect_two_step_cards:
		var two_step_count := _count_invade_cards_with_steps(player, 2)
		for idx in rage_cards:
			# Never discard shin combo reserved cards
			if idx in shin_reserved:
				continue
			var icon: int = player.hand[idx].get("invasion_icon", 0)
			if icon == 2 and two_step_count <= 1:
				continue
			safe_rage_cards.append(idx)
	else:
		for idx in rage_cards:
			if idx in shin_reserved:
				continue
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
	var shin_state: String = _shin_combo_plan.get("state", "")
	var shin_reserved := _get_shin_combo_reserved_indices()

	# Score playable strategies
	if CardEnums.ActionType.PLAY_STRATEGY in valid_actions:
		var playable := rules_engine.get_playable_strategy_cards(player)
		for hand_idx in playable:
			var card: Dictionary = player.hand[hand_idx]
			var score := _score_card(card, player, opponent, near_winning, z8_blocked)
			# Shin combo: boost combo cards when full, penalize when partial
			if shin_state == "full":
				var v: int = maxi(_shin_combo_plan.get("viability", 0), config.shin_combo_full_min_bonus)
				if hand_idx == _shin_combo_plan.get("advance_to_6_idx", -1) \
						or hand_idx == _shin_combo_plan.get("destroy_idx", -1):
					score += v
			elif shin_state == "partial" and hand_idx in shin_reserved:
				score -= config.shin_combo_partial_penalty
			if score > best_score:
				best_score = score
				best_result = [CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx}]

	# Score playable battle cards — plan zone assignments for all cards at once.
	# Zone-preferring cards reserve their zones first, then generic cards pick from the rest.
	if CardEnums.ActionType.PLAY_BATTLE in valid_actions:
		var battle_playable := rules_engine.get_playable_battle_cards(player, opponent)

		# Collect tags for all playable battle cards to detect synergy ordering
		var playable_tags: Dictionary = {}  # hand_idx -> Array[String]
		for hand_idx in battle_playable:
			var b_effect := effect_handler.get_effect(player.hand[hand_idx])
			if b_effect:
				playable_tags[hand_idx] = b_effect.get_bot_tags()
			else:
				playable_tags[hand_idx] = []

		# Build scored entries for all playable battle cards
		var entries: Array[Dictionary] = []
		for hand_idx in battle_playable:
			var b_card: Dictionary = player.hand[hand_idx]
			var valid_zones := rules_engine.get_valid_zones_for_card(b_card, player, opponent)
			if valid_zones.is_empty():
				continue
			var b_score := _score_card(b_card, player, opponent, near_winning, z8_blocked)
			b_score += b_card.get("counter_power", 0) / config.cp_bonus_divisor
			if cp_gap > 0:
				b_score += b_card.get("counter_power", 0) / 500

			# Synergy enabler bonus: if playing this card first would enable synergies
			# for other cards in hand, boost score so it gets played first
			if config.enable_synergies:
				var my_tags: Array = playable_tags.get(hand_idx, [])
				b_score += _score_enabler_bonus(hand_idx, my_tags, playable_tags)

			# Shin combo: boost combo cards when full, penalize when partial
			if shin_state == "full":
				var v: int = maxi(_shin_combo_plan.get("viability", 0), config.shin_combo_full_min_bonus)
				if hand_idx == _shin_combo_plan.get("advance_to_6_idx", -1) \
						or hand_idx == _shin_combo_plan.get("advancement_idx", -1) \
						or hand_idx == _shin_combo_plan.get("destroy_idx", -1):
					b_score += v
			elif shin_state == "partial" and hand_idx in shin_reserved:
				b_score -= config.shin_combo_partial_penalty

			var has_zone_pref := _card_has_zone_preference(b_card)
			entries.append({
				"hand_idx": hand_idx, "card": b_card, "score": b_score,
				"valid_zones": valid_zones, "has_zone_pref": has_zone_pref,
				"rank": b_card.get("rank", 0), "cp": b_card.get("counter_power", 0),
			})

		# Assign zones: prioritized cards first, then generic cards
		var reserved_zones: Dictionary = {}  # zone_idx -> hand_idx
		# Pass 1: zone-preferring cards claim their preferred zones
		for entry in entries:
			if not entry.has_zone_pref or not entry.has_zone_pref:
				continue
			var zone := _pick_battle_zone(entry.valid_zones, player, opponent, entry.card)
			reserved_zones[zone] = entry.hand_idx
			entry["assigned_zone"] = zone

		# Pass 2: generic cards pick zones, avoiding reserved ones
		for entry in entries:
			if entry.has("assigned_zone"):
				continue
			var available: Array[int] = []
			for z in entry.valid_zones:
				if z not in reserved_zones:
					available.append(z)
			if available.is_empty():
				available.assign(entry.valid_zones)  # Fallback: use all zones
			var zone := _pick_battle_zone(available, player, opponent, entry.card)
			entry["assigned_zone"] = zone

		# Pick the best entry: highest score, tiebreak by lower rank, higher CP, random
		var best_rank: int = 999
		var best_cp: int = -1
		for entry in entries:
			var is_better: bool = false
			if entry.score > best_score:
				is_better = true
			elif entry.score == best_score:
				if entry.rank < best_rank:
					is_better = true
				elif entry.rank == best_rank:
					if entry.cp > best_cp:
						is_better = true
					elif entry.cp == best_cp:
						is_better = randi() % 2 == 0
			if is_better:
				best_score = entry.score
				best_rank = entry.rank
				best_cp = entry.cp
				best_result = [CardEnums.ActionType.PLAY_BATTLE, {
					"hand_index": entry.hand_idx, "zone_index": entry.assigned_zone}]

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

	# Penalize unfulfillable triggers — deduct score for each on_* trigger
	# whose bot_can_fulfill_* returns false (the card's effect won't fully fire)
	if config.use_activation_check:
		var triggers: Array = _TriggerMap.TRIGGERS.get(card.get("effect_script", ""), [])
		var has_destroy := "destroys_zone" in tags
		for trigger in triggers:
			var method: StringName = _TRIGGER_FULFILL_MAP.get(trigger, &"")
			if method == &"":
				continue
			var result: bool
			if method == &"bot_can_fulfill_on_phase_start":
				result = effect.call(method, player, opponent, effect_handler)
			else:
				result = effect.call(method, player, opponent)
			if not result:
				if has_destroy and trigger == &"on_enter":
					score -= config.unfulfilled_destroy_penalty
				else:
					score -= config.unfulfilled_trigger_penalty

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
	# Count opponent battle cards in zones this card can actually target
	var effective_target_count: int = opp_zone_count
	if "destroys_zone" in tags:
		var destroy_max_rank: int = -1
		if effect:
			destroy_max_rank = effect.get_bot_destroy_max_rank(player, opponent)
		if "column_dependent_monster_self" in tags:
			var own_monster_idx: int = player.monster_zone - 1
			var column_zones := CardEffect.get_opponent_column_zones(own_monster_idx)
			effective_target_count = 0
			for z in column_zones:
				if _is_valid_destroy_target(opponent, z, destroy_max_rank):
					effective_target_count += 1
		elif "column_dependent_monster" in tags:
			var opp_monster_idx: int = opponent.monster_zone - 1
			var column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
			effective_target_count = 0
			for z in column_zones:
				if _is_valid_destroy_target(opponent, z, destroy_max_rank):
					effective_target_count += 1
		elif destroy_max_rank > 0:
			effective_target_count = 0
			for z in range(8):
				if _is_valid_destroy_target(opponent, z, destroy_max_rank):
					effective_target_count += 1

	for tag in tags:
		if tag == "disrupts_hand" and opp_hand_size >= 5:
			score += 15
		elif tag == "mill_opponent" and opp_deck_size <= 15:
			score += 15
		elif tag == "destroys_zone":
			if effective_target_count >= 5:
				score += 10
			elif effective_target_count == 0:
				# No targets — not worth playing unless duplicate in hand (play to thin)
				var card_id: String = card.get("id", "")
				var copies_in_hand: int = 0
				if not card_id.is_empty():
					for h_card in player.hand:
						if h_card.get("id", "") == card_id:
							copies_in_hand += 1
				if copies_in_hand <= 1:
					score -= 100  # Heavy penalty — don't play with no targets
		elif tag == "weakens_opponent" and opponent.rage >= 3:
			score += 10
		elif tag == "advances_opponent":
			var max_zone: int = -1
			if effect:
				max_zone = effect.get_bot_max_advance_zone(player, opponent)
			var target_zone: int
			if max_zone > 0:
				target_zone = mini(max_zone, opponent.monster_zone + 1)
			else:
				target_zone = opponent.monster_zone + 1
			if target_zone <= opponent.monster_zone:
				score -= 100  # No effect — don't play
			elif target_zone >= 7:
				var can_counter := _can_counter_opponent()
				var crushes_z8 := target_zone >= 8 and opponent.zone_has_battle_card(7)
				var can_win := player.monster_zone >= 7 and (crushes_z8 or not opponent.zone_has_battle_card(7))
				if can_win:
					score += 30  # Setup for the kill
				elif can_counter:
					score += 10  # Safe — we can handle their invasion
				else:
					score -= 50  # Too risky — opponent near winning
		elif tag == "advances_self":
			var max_zone: int = -1
			if effect:
				max_zone = effect.get_bot_max_advance_zone(player, opponent)
			if max_zone > 0 and player.monster_zone >= max_zone:
				score -= 100  # Already past cap — no value
		elif tag == "boosts_cp" and not _can_counter_opponent():
			score += 15

	# Playstyle multipliers — amplify tags that align with the deck's strategy
	if playstyle == Playstyle.INVASION:
		for tag in tags:
			if tag in ["boosts_threat", "disrupts_hand", "destroys_zone", "advances_self",
					"advances_opponent", "weakens_opponent", "mill_opponent", "column_dependent_monster"]:
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


func _is_valid_destroy_target(opp: PlayerState, zone: int, max_rank: int) -> bool:
	var top := opp.get_zone_top_card(zone)
	if top.is_empty():
		return false
	if max_rank > 0 and top.get("rank", 0) > max_rank:
		return false
	return true


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


func _score_enabler_bonus(my_idx: int, my_tags: Array, all_playable_tags: Dictionary) -> int:
	## Bonus for cards that enable synergies for other playable cards in hand.
	## If this card's tags match the synergy_tag another card needs on the board,
	## playing this card first sets up the synergy — boost its score.
	var bonus: int = 0
	for synergy in config.tag_synergies:
		var needed_on_board: String = synergy[1]  # tag the other card wants on the board
		var other_card_tag: String = synergy[0]    # tag the other card must have
		var synergy_bonus: int = synergy[2]
		# Check if this card provides what another card needs on the board
		if needed_on_board not in my_tags:
			continue
		for other_idx in all_playable_tags:
			if other_idx == my_idx:
				continue
			var other_tags: Array = all_playable_tags[other_idx]
			if other_card_tag in other_tags:
				bonus += synergy_bonus
	return bonus


const ZONE_PREF_TAGS: Array[String] = [
	"zone_dependent", "column_dependent_monster", "column_dependent_monster_self",
	"column_dependent_battle", "column_avoid_battle_cards", "avoid_own_adjacent",
]


func _card_has_zone_preference(card: Dictionary) -> bool:
	## Returns true if this card has tags that prefer specific zones.
	var effect := effect_handler.get_effect(card)
	if not effect:
		return false
	var tags := effect.get_bot_tags()
	for tag in tags:
		if tag in ZONE_PREF_TAGS:
			return true
	return false


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


func _get_crush_zone_indices(turns: int = 1) -> Array[int]:
	## Returns 0-indexed zone indices the bot's monster will advance through.
	## turns=1: this end of turn only. turns=2: this turn + next turn.
	var player := game_state.players[bot_player_id]
	var mz := player.monster_zone  # 1-indexed (1-8)
	if mz >= 8:
		return []
	var extra: int = 0
	if effect_handler:
		extra = effect_handler.get_extra_end_phase_advance(bot_player_id)
	var advance_per_turn: int = 1 + extra
	var total_advance: int = advance_per_turn * turns
	var crush_zones: Array[int] = []
	for i in range(1, total_advance + 1):
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
	# Compute effective value of each zone's existing card (base CP + effect contributions)
	var cp_modifiers := effect_handler.get_zone_cp_modifiers(player.player_id)
	var card_cp: int = card.get("counter_power", 0) if not card.is_empty() else 0

	# Never overwrite a zone card with higher effective CP — would reduce net counter power
	var no_loss_zones: Array[int] = []
	for z in valid_zones:
		var zone_card := player.get_zone_top_card(z)
		if zone_card.is_empty():
			no_loss_zones.append(z)
		else:
			var effective_cp: int = zone_card.get("counter_power", 0) + cp_modifiers[z]
			if effective_cp <= card_cp:
				no_loss_zones.append(z)
	if not no_loss_zones.is_empty():
		valid_zones = no_loss_zones

	# Crush zone awareness: avoid zones the monster will advance through in the next 2 turns.
	# Exceptions: zone 8 (won't be crushed), or card nets >= 2000 effective CP over existing.
	var crush_zones := _get_crush_zone_indices(2)
	if not crush_zones.is_empty():
		var safe_zones: Array[int] = []
		for z in valid_zones:
			if z not in crush_zones:
				safe_zones.append(z)
			elif z == 7:
				# Zone 8 (0-indexed 7) — assume it won't be crushed
				safe_zones.append(z)
			elif card_cp >= 2000:
				var existing := player.get_zone_top_card(z)
				var existing_effective: int = 0
				if not existing.is_empty():
					existing_effective = existing.get("counter_power", 0) + cp_modifiers[z]
				if card_cp - existing_effective >= 2000:
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

		# Avoid own adjacent: prefer zones with fewest own adjacent cards
		if "avoid_own_adjacent" in tags:
			var best_z: int = valid_zones[0]
			var best_adj_count: int = 9
			for z in valid_zones:
				var adj_count: int = 0
				for adj_z in CardEffect.get_adjacent_zones(z):
					if player.zone_has_cards(adj_z):
						adj_count += 1
				if adj_count < best_adj_count:
					best_adj_count = adj_count
					best_z = z
			return best_z

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


func _check_shin_combo(player: PlayerState, opponent: PlayerState) -> Dictionary:
	## Check if the bot can set up a "Shin Combo" single-turn win path.
	## Full combo from zone 3-5: advance card #1 → zone 6, card #2 → zone 7,
	##   (destroy z8 if blocked), invade 2-step → zone 9 = victory.
	## From zone 6: only card #2 + (destroy) + invasion needed.
	## Returns a plan dict with state/viability/indices, or empty dict if impossible.

	# Zone 7+ with rank 3+ doesn't need combo (in win position and can't be pushed back)
	# Below rank 3, a successful counter pushes the monster back — keep collecting pieces.
	if player.monster_zone >= 7 and player.current_monster.get("rank", 0) >= 3:
		return {}

	# Required: Find a 2-invasion card in hand
	var invade_idx := _find_invade_card_with_steps(player, 2)
	if invade_idx < 0:
		return {}

	# Opponent zone 8 must be clear or clearable
	var z8_clear := not opponent.zone_has_battle_card(7)
	var destroy_idx: int = -1
	var reserved := [invade_idx]

	if not z8_clear:
		destroy_idx = _find_zone_8_destroy_card(player, opponent, reserved)
	reserved.append(destroy_idx)

	# Find card #2 (advancement card: advances from zone 6 → zone 7+)
	var adv_result := _find_advancement_card(player, opponent, reserved)
	var advancement_idx: int = adv_result[0]
	var advancement_is_monster: bool = adv_result[1]
	reserved.append(advancement_idx)

	# Find card #1 (advance to zone 6) — not needed if already at zone 6
	var advance_to_6_idx: int = -1
	if player.monster_zone < 6:
		advance_to_6_idx = _find_advance_to_zone_6_card(player, opponent, reserved)

	# Determine combo state
	var have_all := invade_idx >= 0 and advancement_idx >= 0 \
			and (z8_clear or destroy_idx >= 0) \
			and (player.monster_zone >= 6 or advance_to_6_idx >= 0)

	if have_all:
		var plan := {
			"state": "full",
			"advance_to_6_idx": advance_to_6_idx,
			"advancement_idx": advancement_idx,
			"advancement_is_monster": advancement_is_monster,
			"destroy_idx": destroy_idx,
			"invade_idx": invade_idx,
		}
		plan["viability"] = _compute_shin_combo_viability(player, opponent, plan)
		return plan

	# Check for partial combo — some pieces in hand, rest in deck
	var missing_in_deck := _scan_deck_for_combo_pieces(player, opponent,
			advancement_idx < 0, not z8_clear and destroy_idx < 0,
			player.monster_zone < 6 and advance_to_6_idx < 0)
	if missing_in_deck:
		# Proactively reserve a destroy card even if z8 is currently clear —
		# opponent may fill it before the combo assembles.
		var plan_destroy_idx := destroy_idx
		if plan_destroy_idx < 0:
			var partial_reserved := [invade_idx, advancement_idx, advance_to_6_idx]
			plan_destroy_idx = _find_any_destroy_card(player, partial_reserved)
		return {
			"state": "partial",
			"advance_to_6_idx": advance_to_6_idx,
			"advancement_idx": advancement_idx,
			"advancement_is_monster": advancement_is_monster,
			"destroy_idx": plan_destroy_idx,
			"invade_idx": invade_idx,
			"viability": 0,
		}

	return {}


func _find_advancement_card(player: PlayerState, opponent: PlayerState,
		reserved: Array) -> Array:
	## Find card #2: a playable card with "advances_self" and max_advance_zone >= 7 or == -1.
	## Searches battle cards, strategy cards, and playable monsters.
	## Returns [hand_idx, is_monster] or [-1, false].
	##
	## Card #2 fires AFTER card #1 advances monster to zone 6, so evaluate
	## get_bot_max_advance_zone as if monster is already at zone 6.
	var saved_zone := player.monster_zone
	player.monster_zone = maxi(saved_zone, 6)
	var result := _find_advancement_card_at_zone_6(player, opponent, reserved)
	player.monster_zone = saved_zone
	return result


func _find_advancement_card_at_zone_6(player: PlayerState, opponent: PlayerState,
		reserved: Array) -> Array:
	## Inner search for _find_advancement_card (called with monster_zone set to 6+).

	# Check playable battle cards
	var playable_battles := rules_engine.get_playable_battle_cards(player, opponent)
	for hand_idx in playable_battles:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "advances_self" not in tags:
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 7:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return [hand_idx, false]

	# Check playable strategy cards
	var playable_strategies := rules_engine.get_playable_strategy_cards(player)
	for hand_idx in playable_strategies:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "advances_self" not in tags:
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 7:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return [hand_idx, false]

	# Check ALL monster cards in hand (not just currently playable ones — the combo
	# involves playing card #1 first, then ranking up to the advancement monster).
	for hand_idx in range(player.hand.size()):
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "advances_self" not in tags:
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 7:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return [hand_idx, true]

	return [-1, false]


func _scan_deck_for_combo_pieces(player: PlayerState, _opponent: PlayerState,
		need_advancement: bool, need_destroy: bool, need_advance_to_6: bool) -> bool:
	## Scan the deck for missing combo pieces. Returns true if all missing pieces
	## exist somewhere in the deck (so they can be drawn into later).
	## Evaluates advancement cards as if monster is at zone 6 (same as _find_advancement_card).
	var found_advancement := not need_advancement
	var found_destroy := not need_destroy
	var found_advance_to_6 := not need_advance_to_6

	var saved_zone := player.monster_zone
	for card in player.main_deck:
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()

		if not found_advancement and "advances_self" in tags:
			# Evaluate from zone 6 (card #2 fires after card #1 advances to 6)
			player.monster_zone = maxi(saved_zone, 6)
			var max_zone: int = effect.get_bot_max_advance_zone(player, _opponent)
			player.monster_zone = saved_zone
			if max_zone == -1 or max_zone >= 7:
				found_advancement = true

		if not found_destroy and "destroys_zone" in tags:
			found_destroy = true

		if not found_advance_to_6 and "advances_self" in tags:
			var max_zone: int = effect.get_bot_max_advance_zone(player, _opponent)
			if max_zone == -1 or max_zone >= 6:
				found_advance_to_6 = true

		if found_advancement and found_destroy and found_advance_to_6:
			return true

	return found_advancement and found_destroy and found_advance_to_6


func _compute_shin_combo_viability(player: PlayerState, opponent: PlayerState,
		plan: Dictionary) -> int:
	## Compute viability score (0-150) for a full shin combo.
	## Factors: proximity, opponent pressure, zone 8 clear, hand flexibility, CP advantage.
	var score: int = 0

	# Proximity: +30 to +80 based on monster zone (3-6)
	var zone_idx: int = player.monster_zone - 3
	if zone_idx >= 0 and zone_idx < config.shin_combo_proximity_scores.size():
		score += config.shin_combo_proximity_scores[zone_idx]

	# Opponent pressure: based on opponent monster zone
	var pressure_bonus: int = 0
	if opponent.monster_zone <= 4:
		pressure_bonus = config.shin_combo_low_pressure_bonus  # +20
	elif opponent.monster_zone <= 6:
		pressure_bonus = 0
	elif opponent.monster_zone == 7:
		pressure_bonus = -config.shin_combo_high_pressure_penalty  # -20
	else:
		pressure_bonus = -config.shin_combo_critical_pressure_penalty  # -40
	# Halve penalty if bot can counter
	if pressure_bonus < 0 and _can_counter_opponent():
		pressure_bonus /= 2
	score += pressure_bonus

	# Zone 8 clear bonus: +20 if no destroy card needed
	if plan.get("destroy_idx", -1) == -1:
		score += config.shin_combo_z8_clear_bonus

	# Hand flexibility penalty: based on remaining cards after combo pieces used
	var combo_pieces: int = 1  # invasion card always needed
	if plan.get("advance_to_6_idx", -1) >= 0:
		combo_pieces += 1
	if plan.get("advancement_idx", -1) >= 0:
		combo_pieces += 1
	if plan.get("destroy_idx", -1) >= 0:
		combo_pieces += 1
	var remaining: int = player.hand.size() - combo_pieces
	if remaining >= 5:
		score -= 10
	elif remaining >= 3:
		score -= 15
	elif remaining >= 1:
		score -= 25
	else:
		score -= 30

	# CP advantage penalty: if in COUNTER phase and behind on CP
	var cp_gap := _get_cp_gap()
	if cp_gap >= 10000:
		score -= 30
	elif cp_gap >= 5000:
		score -= 15

	# Invasion blocked: heavy penalty if own invasion is blocked by effects
	if effect_handler.is_own_invasion_blocked(player.player_id):
		score -= 100

	return maxi(score, 0)


func _get_shin_combo_reserved_indices() -> Array[int]:
	## Returns all hand indices reserved by the shin combo plan (full or partial).
	var reserved: Array[int] = []
	if _shin_combo_plan.is_empty():
		return reserved
	for key in ["advance_to_6_idx", "advancement_idx", "destroy_idx", "invade_idx"]:
		var idx: int = _shin_combo_plan.get(key, -1)
		if idx >= 0:
			reserved.append(idx)
	return reserved


func _find_any_destroy_card(player: PlayerState, reserved: Array) -> int:
	## Find any card in hand with "destroys_zone" tag, excluding reserved indices.
	## Used for proactive destroy card reservation in partial combo state.
	for hand_idx in range(player.hand.size()):
		if hand_idx in reserved:
			continue
		var effect := effect_handler.get_effect(player.hand[hand_idx])
		if not effect:
			continue
		if "destroys_zone" in effect.get_bot_tags():
			return hand_idx
	return -1


func _find_zone_8_destroy_card(player: PlayerState, opponent: PlayerState, reserved: Array) -> int:
	## Find a playable card in hand that can destroy the opponent's zone 8 battle card.
	## Returns hand index, or -1 if none found.
	var z8_card := opponent.get_zone_top_card(7)
	if z8_card.is_empty():
		return -1
	var z8_rank: int = z8_card.get("rank", 0)

	# Check playable battle cards
	var playable_battles := rules_engine.get_playable_battle_cards(player, opponent)
	for hand_idx in playable_battles:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "destroys_zone" not in tags:
			continue
		# Check rank restriction — can this card destroy zone 8's card?
		var max_rank: int = effect.get_bot_destroy_max_rank(player, opponent)
		if max_rank > 0 and z8_rank > max_rank:
			continue
		# Check fulfillment
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	# Check playable strategy cards
	var playable_strategies := rules_engine.get_playable_strategy_cards(player)
	for hand_idx in playable_strategies:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "destroys_zone" not in tags:
			continue
		var max_rank: int = effect.get_bot_destroy_max_rank(player, opponent)
		if max_rank > 0 and z8_rank > max_rank:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	return -1


func _find_advance_to_zone_6_card(player: PlayerState, opponent: PlayerState,
		reserved: Array) -> int:
	## Find a playable card with "advances_self" that can advance to zone 6+.
	## Excludes cards reserved for other combo roles.
	var playable_battles := rules_engine.get_playable_battle_cards(player, opponent)
	for hand_idx in playable_battles:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "advances_self" not in tags:
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 6:
			continue
		# Check fulfillment
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	# Also check playable strategy cards with advances_self
	var playable_strategies := rules_engine.get_playable_strategy_cards(player)
	for hand_idx in playable_strategies:
		if hand_idx in reserved:
			continue
		var card: Dictionary = player.hand[hand_idx]
		var effect := effect_handler.get_effect(card)
		if not effect:
			continue
		var tags: Array[String] = effect.get_bot_tags()
		if "advances_self" not in tags:
			continue
		var max_zone: int = effect.get_bot_max_advance_zone(player, opponent)
		if max_zone != -1 and max_zone < 6:
			continue
		if effect.has_method(&"bot_can_fulfill_on_enter"):
			if not effect.bot_can_fulfill_on_enter(player, opponent):
				continue
		return hand_idx

	return -1


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
	## Shin combo reserved cards are protected — discarded only as a last resort.
	var opponent := game_state.players[1 - bot_player_id]
	var shin_reserved := _get_shin_combo_reserved_indices()
	var monster_indices: Array[int] = []
	var non_playable_indices: Array[int] = []
	var playable_indices: Array[int] = []
	var protected_indices: Array[int] = []

	# Categorize hand cards
	var playable_battles := rules_engine.get_playable_battle_cards(player, opponent)
	var playable_strategies := rules_engine.get_playable_strategy_cards(player)
	var playable_set: Dictionary = {}
	for idx in playable_battles:
		playable_set[idx] = true
	for idx in playable_strategies:
		playable_set[idx] = true

	for i in range(player.hand.size()):
		# Shin combo pieces go to a protected pool (discarded last)
		if i in shin_reserved:
			protected_indices.append(i)
			continue
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
	# Last resort: if still need more, discard protected shin combo pieces
	for idx in protected_indices:
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
	# Prefer non-combo-reserved cards; fall back to reserved only if no alternative
	var player := game_state.players[bot_player_id]
	var shin_reserved := _get_shin_combo_reserved_indices()
	var safe_indices: Array[int] = []
	for idx in valid_indices:
		if idx not in shin_reserved:
			safe_indices.append(idx)
	var pick_from: Array[int] = safe_indices if not safe_indices.is_empty() else valid_indices
	# Pick the hand card with highest CP/threat, lowest rank
	var best_idx: int = pick_from[0]
	var best_val: int = _card_sort_value(player.hand[best_idx])
	for i in range(1, pick_from.size()):
		var idx: int = pick_from[i]
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

	# Priority 2: destroy the zone with highest total CP (card + adjacent cards)
	# Adjacent CP acts as tiebreaker — maximizes value for effects that also hit neighbors
	var cp_modifiers := effect_handler.get_zone_cp_modifiers(opponent.player_id)
	var max_rank: int = effect_handler.pending_destroy_max_rank
	var best_zone: int = valid_zones[0]
	var best_cp: int = -1
	var best_adj_cp: int = -1
	for z in valid_zones:
		var zone_card := opponent.get_zone_top_card(z)
		if zone_card.is_empty():
			continue
		if max_rank > 0 and zone_card.get("rank", 0) > max_rank:
			continue
		var cp: int = zone_card.get("counter_power", 0) + cp_modifiers[z]
		# Sum adjacent zones' CP as tiebreaker
		var adj_cp: int = 0
		for adj_z in CardEffect.get_adjacent_zones(z):
			var adj_card := opponent.get_zone_top_card(adj_z)
			if not adj_card.is_empty():
				if max_rank > 0 and adj_card.get("rank", 0) > max_rank:
					continue
				adj_cp += adj_card.get("counter_power", 0) + cp_modifiers[adj_z]
		if cp > best_cp or (cp == best_cp and adj_cp > best_adj_cp):
			best_cp = cp
			best_adj_cp = adj_cp
			best_zone = z

	# If all valid zones are empty, pick one in the bot's invasion path
	if best_cp < 0:
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
