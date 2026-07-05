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

# Combo system — detects multi-card win paths, protects pieces, boosts scores.
var _combos: Array[BotCombo] = []
var _active_combo_plan: Dictionary = {}
var combo_stats: Dictionary = {
	"detected": 0, "full": 0, "partial": 0, "executed": 0,
	"max_viability": 0,
}
## Key moment log — array of strings describing game state at critical decisions.
var combo_log: Array[String] = []

var game_state: GameState
var rules_engine: RulesEngine
var turn_manager: TurnManager
var action_handler: ActionHandler
var effect_handler: EffectHandler
var player_input: SignalPlayerInput
var scene_tree: SceneTree
var _invasion: RefCounted = null
var _zones: RefCounted = null

# Split-out decision helpers (see scripts/bot/README.md)
var _scoring: RefCounted = null


func _init() -> void:
	_invasion = preload("res://scripts/bot/bot_invasion.gd").new(self)
	_zones = preload("res://scripts/bot/bot_zone_picker.gd").new(self)
	_scoring = preload("res://scripts/bot/bot_scoring.gd").new(self)



func init_combos() -> void:
	## Initialize combo detectors based on difficulty config. Call after game setup.
	## Only enables combos if the deck has the required pieces.
	_combos.clear()
	var player := game_state.players[bot_player_id]
	for combo_name in config.enabled_combos:
		match combo_name:
			"shin":
				var shin := BotComboShin.new()
				if shin.is_deck_compatible(player, self):
					shin.enabled = true
					_combos.append(shin)
					print("[Bot] Shin combo enabled — deck has counter-retreat path")
				else:
					print("[Bot] Shin combo skipped — deck lacks key pieces")


func analyze_deck() -> void:
	## Scan all cards in the bot's deck + hand to determine playstyle.
	## Call after game setup when deck is populated.
	init_combos()
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
	if scene_tree:
		if config.action_delay > 0:
			await scene_tree.create_timer(config.action_delay).timeout
		else:
			await Engine.get_main_loop().process_frame


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
	var cp_gap := get_cp_gap()  # positive = behind on CP, needs defense
	var needs_defense := cp_gap > 0

	# 0. Combo check — detect multi-card win paths
	_active_combo_plan = {}
	for combo in _combos:
		if not combo.enabled:
			continue
		var plan := combo.check(player, opponent, self)
		if plan.is_empty():
			continue
		if _active_combo_plan.is_empty() \
				or (plan.get("state") == "full" and _active_combo_plan.get("state") != "full") \
				or (plan.get("state") == "full" and plan.get("viability", 0) > _active_combo_plan.get("viability", 0)):
			_active_combo_plan = plan
	if not _active_combo_plan.is_empty():
		print("[Bot] Combo detected: %s state=%s viability=%d" % [
			_active_combo_plan.get("combo_name", "?"),
			_active_combo_plan.get("state", "?"),
			_active_combo_plan.get("viability", 0)])
		combo_stats["detected"] += 1
		var viability: int = _active_combo_plan.get("viability", 0)
		if viability > combo_stats["max_viability"]:
			combo_stats["max_viability"] = viability
		if _active_combo_plan.get("state") == "full":
			combo_stats["full"] += 1
			if combo_stats["full"] == 1:
				_combo_log_state("FIRST_FULL")
		elif _active_combo_plan.get("state") == "partial":
			combo_stats["partial"] += 1

	var combo_monster_rules := _get_combo_monster_rules(player)

	# Downgrade full → partial for scoring if combo can't execute yet
	# (e.g. advancement monster not playable). Pieces stay protected.
	# Exception: counter-retreat path doesn't need hand-playable advancement.
	if _active_combo_plan.get("state") == "full" \
			and not _active_combo_plan.get("counter_retreat_path", false) \
			and combo_monster_rules.get("force_play_idx", -1) < 0 \
			and combo_monster_rules.get("skip_all", false):
		_active_combo_plan["state"] = "partial"

	# 1. Play monster if available (increases rage/threat, no downside)
	#    Combo system may skip, force, or exclude specific monsters.
	if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
		if not combo_monster_rules.get("skip_all", false):
			var force_idx: int = combo_monster_rules.get("force_play_idx", -1)
			if force_idx >= 0:
				return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": force_idx}]
			var playable := rules_engine.get_playable_monsters(player)
			var exclude_idx: int = combo_monster_rules.get("exclude_idx", -1)
			if exclude_idx >= 0:
				playable = playable.filter(func(idx: int) -> bool: return idx != exclude_idx)
			if not playable.is_empty():
				return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": playable[0]}]

	# 2. Win check: zone 7+ and opponent zone 8 empty → invade to win immediately
	#    No exclusions — winning is always top priority.
	if CardEnums.ActionType.INVADE in valid_actions:
		if player.monster_zone >= 7 and not z8_blocked:
			var win_invade_idx := _find_best_invade_card(player)
			if win_invade_idx >= 0:
				return [CardEnums.ActionType.INVADE, {"hand_index": win_invade_idx}]

	# 2.5. Combo execution: play combo pieces in sequence when all key pieces are ready.
	#       This overrides normal card scoring to enforce correct play order.
	if not _active_combo_plan.is_empty():
		var combo_exec := _get_combo_execution_action(valid_actions, player, opponent)
		if not combo_exec.is_empty():
			combo_stats["executed"] += 1
			_combo_log_state("EXEC_%s" % CardEnums.ActionType.keys()[combo_exec[0]])
			return combo_exec

	# 3. Aggressive: INVASION playstyle tries to invade early with 2-step cards.
	#    Skip when combo prefers 1-step (saves 2-step cards for the win).
	var combo_inv_excludes := _get_combo_invasion_excludes()
	var combo_suppress := _should_combo_suppress_invasion(player, opponent)
	var combo_pref := _get_combo_invasion_preference()
	var combo_prefers_1step: bool = combo_pref.get("preferred_steps", 0) == 1
	if config.use_early_invasion and playstyle == Playstyle.INVASION and not combo_prefers_1step:
		if CardEnums.ActionType.INVADE in valid_actions:
			if not combo_suppress:
				if player.monster_zone <= config.early_invasion_zone_threshold \
						or (player.monster_zone == config.early_invasion_zone_threshold + 1 \
						and randf() < config.zone_6_two_step_chance):
					var two_step_idx := find_invade_card_with_steps(player, 2, combo_inv_excludes)
					if two_step_idx >= 0:
						var monsters := _count_monster_cards_in_hand(player)
						if not _invasion_blocked_by_rage(player, two_step_idx, monsters):
							return [CardEnums.ActionType.INVADE, {"hand_index": two_step_idx}]

	# 4. Combo cycling: gain rage to dig for combo pieces before playing cards.
	#    This trades a monster card for rage + draws at end of turn.
	var combo_cycling := _should_combo_prioritize_cycling(player, opponent)
	if combo_cycling and CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_result := _try_gain_rage(player)
		if not rage_result.is_empty():
			_combo_log_state("CYCLE")
			return rage_result

	# 5. When ahead on CP, gain rage early to build threat before playing cards
	if not combo_cycling and not needs_defense \
			and CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_result := _try_gain_rage(player)
		if not rage_result.is_empty():
			return rage_result

	# 6. Score all playable cards and play the highest-value one
	var best_action := _decide_best_card_play(valid_actions, player, opponent, near_winning, z8_blocked, cp_gap)
	if not best_action.is_empty():
		return best_action

	# 7. Gain rage (when behind on CP, rage was skipped earlier — try now as fallback)
	if needs_defense and CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_result := _try_gain_rage(player)
		if not rage_result.is_empty():
			return rage_result

	# 7. Invade based on position and playstyle (skip when behind on CP)
	#    - INVASION: always tries to invade strategically
	#    - BALANCED: invades unless a base strategy is in play (when config allows)
	#    - COUNTER: never invades here (only for the win in step 5)
	#    Combo may suppress invasion (e.g. pace-matching in early zones).
	if not needs_defense and not combo_suppress \
			and CardEnums.ActionType.INVADE in valid_actions:
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
	var combo_reserved := _get_combo_reserved_indices()
	if config.protect_two_step_cards:
		var two_step_count := _count_invade_cards_with_steps(player, 2)
		for idx in rage_cards:
			if idx in combo_reserved:
				continue
			var icon: int = player.hand[idx].get("invasion_icon", 0)
			if icon == 2 and two_step_count <= 1:
				continue
			safe_rage_cards.append(idx)
	else:
		for idx in rage_cards:
			if idx in combo_reserved:
				continue
			safe_rage_cards.append(idx)

	if safe_rage_cards.is_empty():
		return []

	# Invasion playstyle with only monsters: keep best invasion card, discard worst
	if playstyle == Playstyle.INVASION and _all_hand_cards_are_monsters(player):
		if safe_rage_cards.size() > 1 or _find_best_invade_card(player) < 0:
			var worst_invade_idx := _find_worst_invade_card(safe_rage_cards, player)
			return [CardEnums.ActionType.GAIN_RAGE, {"hand_index": worst_invade_idx}]
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
	## Cards with score <= 0 are never played (e.g. combo-reserved cards with heavy penalty).
	var best_score: int = 0
	var best_result: Array = []
	# Score playable strategies
	if CardEnums.ActionType.PLAY_STRATEGY in valid_actions:
		var playable := rules_engine.get_playable_strategy_cards(player)
		for hand_idx in playable:
			var card: Dictionary = player.hand[hand_idx]
			var score := _score_card(card, player, opponent, near_winning, z8_blocked)
			score = _get_combo_adjusted_score(hand_idx, score)
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
			var b_cp: int = b_card.get("counter_power", 0)
			b_score += int(b_cp / float(config.cp_bonus_divisor))
			# Scale CP bonus with how far behind we are
			if cp_gap > 0:
				b_score += int(b_cp * mini(cp_gap, 20000) / 10000.0)
			# Emergency CP: when opponent at z7+, heavily weight CP to survive invasion
			if opponent.monster_zone >= 7:
				b_score += int(b_cp / 200.0)

			# Synergy enabler bonus: if playing this card first would enable synergies
			# for other cards in hand, boost score so it gets played first
			if config.enable_synergies:
				var my_tags: Array = playable_tags.get(hand_idx, [])
				b_score += _score_enabler_bonus(hand_idx, my_tags, playable_tags)

			# Combo score adjustment (boost when full, penalize when partial)
			b_score = _get_combo_adjusted_score(hand_idx, b_score)

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
	return _scoring._score_card(card, player, opponent, near_winning, z8_blocked)


func _score_from_triggers(card: Dictionary, opponent: PlayerState) -> int:
	return _scoring._score_from_triggers(card, opponent)


func _is_valid_destroy_target(opp: PlayerState, zone: int, max_rank: int) -> bool:
	return _zones._is_valid_destroy_target(opp, zone, max_rank)


func _score_synergies(card_tags: Array[String], player: PlayerState, _opponent: PlayerState) -> int:
	return _scoring._score_synergies(card_tags, player, _opponent)


func _score_enabler_bonus(my_idx: int, my_tags: Array, all_playable_tags: Dictionary) -> int:
	return _scoring._score_enabler_bonus(my_idx, my_tags, all_playable_tags)


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
	return _zones._get_crush_zone_indices(turns)


func _combo_log_state(event: String) -> void:
	## Log a game state snapshot at a key combo moment.
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	var cp: int = player.get_total_counter_power()
	cp += effect_handler.get_counter_power_modifier(player.player_id)
	var threat: int = player.get_threat_level()
	threat += effect_handler.get_threat_level_modifier(player.player_id)
	var opp_threat: int = opponent.get_threat_level()
	opp_threat += effect_handler.get_threat_level_modifier(opponent.player_id)
	var opp_cp: int = opponent.get_total_counter_power()
	opp_cp += effect_handler.get_counter_power_modifier(opponent.player_id)
	var strats: int = 0
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			strats += 1
	combo_log.append("T%d %s | z%d(r%d) hand=%d strats=%d rage=%d CP=%d threat=%d | opp z%d CP=%d threat=%d | combo=%s viab=%d" % [
		game_state.turn_number, event,
		player.monster_zone, player.current_monster.get("rank", 0),
		player.hand.size(), strats, player.rage, cp, threat,
		opponent.monster_zone, opp_cp, opp_threat,
		_active_combo_plan.get("state", "none"),
		_active_combo_plan.get("viability", 0)])


func get_cp_gap() -> int:
	## Returns opponent threat minus bot CP. Positive = bot is behind, negative/zero = bot is ahead.
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	var total_cp: int = player.get_total_counter_power()
	total_cp += effect_handler.get_counter_power_modifier(player.player_id)
	var threat: int = opponent.get_threat_level()
	threat += effect_handler.get_threat_level_modifier(opponent.player_id)
	return threat - total_cp


func can_counter_opponent() -> bool:
	## Returns true if the bot's current counter power meets or exceeds the opponent's threat.
	return get_cp_gap() <= 0


func _pick_battle_zone(valid_zones: Array[int], player: PlayerState, opponent: PlayerState, card: Dictionary = {}) -> int:
	return _zones._pick_battle_zone(valid_zones, player, opponent, card)


func _get_zone_priority(monster_zone: int) -> Array[int]:
	return _zones._get_zone_priority(monster_zone)


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
	return _invasion._invasion_blocked_by_rage(player, inv_idx, monsters_in_hand)


func _count_invade_cards_with_steps(player: PlayerState, steps: int) -> int:
	return _invasion._count_invade_cards_with_steps(player, steps)


func _find_worst_invade_card(indices: Array, player: PlayerState) -> int:
	return _invasion._find_worst_invade_card(indices, player)


func _find_best_invade_card(player: PlayerState, exclude: Array = []) -> int:
	return _invasion._find_best_invade_card(player, exclude)


func _is_invade1_cost_blocked(player: PlayerState) -> bool:
	return _invasion._is_invade1_cost_blocked(player)


func _ensure_combo_plan() -> void:
	## Ensure combo plan is populated. Called before any card selection/discard
	## that might happen before _decide_main_action (e.g. start-of-turn effects).
	if not _active_combo_plan.is_empty():
		return
	if _combos.is_empty():
		return
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	for combo in _combos:
		if not combo.enabled:
			continue
		var plan := combo.check(player, opponent, self)
		if plan.is_empty():
			continue
		if _active_combo_plan.is_empty() \
				or (plan.get("state") == "full" and _active_combo_plan.get("state") != "full") \
				or (plan.get("state") == "full" and plan.get("viability", 0) > _active_combo_plan.get("viability", 0)):
			_active_combo_plan = plan


func _get_combo_reserved_indices() -> Array[int]:
	## Returns hand indices reserved by the active combo plan.
	## Full state: all reserved. Partial: only critical pieces (invasion + advancement).
	_ensure_combo_plan()
	if _active_combo_plan.get("state") == "full":
		var reserved: Array[int] = []
		reserved.assign(_active_combo_plan.get("reserved_indices", []))
		return reserved
	# Partial: delegate to the combo for which pieces are critical
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_partial_reserved_indices(_active_combo_plan)
	return []


func _get_combo_invasion_excludes() -> Array[int]:
	## Returns hand indices excluded from invasion use.
	## Only excludes in full state — partial shouldn't block invasion.
	if _active_combo_plan.get("state") != "full":
		return []
	var reserved: Array[int] = []
	reserved.assign(_active_combo_plan.get("reserved_indices", []))
	return reserved


func _get_combo_score_adjustment(hand_idx: int) -> int:
	## Returns score adjustment for a card from the active combo.
	if _active_combo_plan.is_empty():
		return 0
	var name: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == name:
			return combo.get_score_adjustment(_active_combo_plan, hand_idx)
	return 0


func _get_combo_adjusted_score(hand_idx: int, base_score: int) -> int:
	## Returns context-aware adjusted score from the active combo.
	if _active_combo_plan.is_empty():
		return base_score
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.adjust_card_score(_active_combo_plan, hand_idx, base_score,
					player, opponent)
	return base_score


func _get_combo_invasion_preference() -> Dictionary:
	## Returns invasion guidance from the active combo.
	if _active_combo_plan.is_empty():
		return {"preferred_steps": 0, "max_zone": -1, "target_zone": -1}
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	var player := game_state.players[bot_player_id]
	var opponent := game_state.players[1 - bot_player_id]
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_invasion_preference(_active_combo_plan, player, opponent)
	return {"preferred_steps": 0, "max_zone": -1, "target_zone": -1}


func _get_combo_battle_zone_avoidance() -> Array[int]:
	## Returns zones to avoid placing battle cards in (combo will crush them).
	if _active_combo_plan.is_empty():
		return []
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	var player := game_state.players[bot_player_id]
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_battle_zone_avoidance(_active_combo_plan, player)
	return []


func _should_combo_prioritize_cycling(player: PlayerState, opponent: PlayerState) -> bool:
	## Ask the active combo if the bot should cycle hand (gain rage) before playing cards.
	if _active_combo_plan.is_empty():
		return false
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.should_prioritize_cycling(_active_combo_plan, player, opponent)
	return false


func _get_combo_execution_action(valid_actions: Array, player: PlayerState,
		opponent: PlayerState) -> Array:
	## Ask the active combo for the next forced action in the execution sequence.
	if _active_combo_plan.is_empty():
		return []
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_execution_action(_active_combo_plan, valid_actions,
					player, opponent, self)
	return []


func _get_combo_monster_rules(player: PlayerState) -> Dictionary:
	## Returns monster play rules from the active combo.
	if _active_combo_plan.is_empty():
		return {}
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_monster_play_rules(_active_combo_plan, player, self)
	return {}


func _should_combo_suppress_invasion(player: PlayerState, opponent: PlayerState) -> bool:
	## Ask the active combo if invasion should be suppressed this frame.
	if _active_combo_plan.is_empty():
		return false
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.should_suppress_invasion(_active_combo_plan, player, opponent)
	return false


func _decide_invade(player: PlayerState, opponent: PlayerState) -> Array:
	return _invasion._decide_invade(player, opponent)


func find_invade_card_with_steps(player: PlayerState, steps: int, exclude: Array = []) -> int:
	return _invasion.find_invade_card_with_steps(player, steps, exclude)


func _on_confirmation_requested(_prompt: String, _setting: String) -> void:
	if not is_bot_turn():
		return
	await _delay()
	player_input.resolve_confirmation()


# --- Monster rank-up ---

func _on_monster_rankup_requested(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	_combo_log_state("RANKUP")
	var best := _score_rankup_candidates(monsters, valid_indices)
	player_input.resolve_monster_rankup(best)


func _score_rankup_candidates(monsters: Array[Dictionary], valid_indices: Array[int]) -> int:
	return _scoring._score_rankup_candidates(monsters, valid_indices)


func _get_combo_rankup_bonus(monster: Dictionary, player: PlayerState,
		opponent: PlayerState) -> int:
	## Ask all active combos for rank-up preference on this monster.
	if _active_combo_plan.is_empty():
		return 0
	var combo_name_key: String = _active_combo_plan.get("combo_name", "")
	for combo in _combos:
		if combo.combo_name == combo_name_key:
			return combo.get_rankup_bonus(_active_combo_plan, monster,
					player, opponent, self)
	return 0


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
	player_input.resolve_choice(pick)


func _score_choice_options(options: Array[String]) -> int:
	return _scoring._score_choice_options(options)


func _pick_zone_choice(options: Array[String], opponent: PlayerState) -> int:
	return _zones._pick_zone_choice(options, opponent)


func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	var player := game_state.players[bot_player_id]
	var indices: Array[int] = _pick_discard_indices(player, discard_count)
	player_input.resolve_hand_discard(bot_player_id, indices)


func _pick_discard_indices(player: PlayerState, count: int) -> Array[int]:
	## Priority: monster cards first, then non-playable cards, then random.
	## Shin combo reserved cards are protected — discarded only as a last resort.
	var opponent := game_state.players[1 - bot_player_id]
	var combo_reserved := _get_combo_reserved_indices()
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
		if i in combo_reserved:
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
	return _scoring._card_sort_value(card)


func _pick_best_card(cards: Array[Dictionary]) -> Dictionary:
	return _scoring._pick_best_card(cards)


func _sort_cards_by_value(cards: Array[Dictionary]) -> Array[Dictionary]:
	return _scoring._sort_cards_by_value(cards)


func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], prompt: String, _allow_skip: bool = true) -> void:
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
	player_input.resolve_deck_search(selected)


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

	player_input.resolve_deck_arrange(keep, discard)


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
	player_input.resolve_card_select(selected)


# --- Hand card selection ---

func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], _prompt: String, _allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_indices.is_empty():
		player_input.resolve_hand_card_selection(-1)
		return
	var player := game_state.players[bot_player_id]
	# Protect combo pieces: recompute reserved indices fresh (hand may have changed
	# since _decide_main_action) and also protect the last 2-step invasion card.
	_active_combo_plan = {}  # Force recompute with current hand state
	var combo_reserved := _get_combo_reserved_indices()
	var safe_indices: Array[int] = []
	for idx in valid_indices:
		if idx in combo_reserved:
			continue
		# Protect last 2-step invasion card even if not in combo plan
		if _is_last_two_step_card(player, idx):
			continue
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
	player_input.resolve_hand_card_selection(best_idx)


func _is_last_two_step_card(player: PlayerState, hand_idx: int) -> bool:
	return _invasion._is_last_two_step_card(player, hand_idx)


func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], _prompt: String, allow_skip: bool) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if valid_zones.is_empty() and allow_skip:
		player_input.resolve_zone_target(-1)
	elif not valid_zones.is_empty():
		var player := game_state.players[bot_player_id]
		var opponent := game_state.players[1 - bot_player_id]

		if target_player_id != bot_player_id:
			# Targeting opponent's zones — pick strategically
			player_input.resolve_zone_target(_pick_opponent_zone_target(valid_zones, player, opponent))
		else:
			# Targeting own zones — use existing priority logic
			player_input.resolve_zone_target(_pick_own_zone_target(valid_zones, player))
	else:
		player_input.resolve_zone_target(-1)


func _pick_opponent_zone_target(valid_zones: Array[int], player: PlayerState, opponent: PlayerState) -> int:
	return _zones._pick_opponent_zone_target(valid_zones, player, opponent)


func _pick_own_zone_target(valid_zones: Array[int], player: PlayerState) -> int:
	return _zones._pick_own_zone_target(valid_zones, player)


func _on_strategy_target_requested(player_id: int, _target_player_id: int, valid_indices: Array[int], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	if not valid_indices.is_empty():
		player_input.resolve_strategy_target(valid_indices[0])


# --- Cards revealed ---

func _on_cards_revealed_requested(player_id: int, _cards: Array[Dictionary], _title: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	player_input.resolve_cards_revealed()
