class_name BotPlayer
extends RefCounted

## AI bot that controls Player 2 in Solo v Bot mode.
## Connects to the same signals as game_board.gd and calls resolve methods directly.

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

enum Playstyle { INVASION, COUNTER, BALANCED }

var bot_player_id: int = 1
var action_delay: float = 0.5
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
	var player := game_state.players[bot_player_id]
	var all_cards: Array[Dictionary] = []
	all_cards.append_array(player.hand)
	all_cards.append_array(player.deck)

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
		var tags: Array[String] = effect.get_bot_tags() if effect else []

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
	elif invasion_score / total >= 0.6:
		playstyle = Playstyle.INVASION
	elif counter_score / total >= 0.6:
		playstyle = Playstyle.COUNTER
	else:
		playstyle = Playstyle.BALANCED

	print("[Bot] Deck analysis — invasion: %.1f, counter: %.1f, playstyle: %s" % [
		invasion_score, counter_score, Playstyle.keys()[playstyle]])


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
	var near_winning := player.monster_zone >= 6
	var z8_blocked := opponent.zone_has_battle_card(7)

	# 1. Play monster if available (increases rage/threat, no downside)
	if CardEnums.ActionType.PLAY_MONSTER in valid_actions:
		var playable := rules_engine.get_playable_monsters(player)
		if not playable.is_empty():
			return [CardEnums.ActionType.PLAY_MONSTER, {"hand_index": playable[0]}]

	# 2. Aggressive: try to invade for the win before playing cards
	if playstyle == Playstyle.INVASION:
		if CardEnums.ActionType.INVADE in valid_actions:
			if player.monster_zone >= 7 and not z8_blocked:
				var invade_idx := _find_best_invade_card(player)
				if invade_idx >= 0:
					return [CardEnums.ActionType.INVADE, {"hand_index": invade_idx}]

	# 3. Score all playable cards and play the highest-value one
	var best_action := _decide_best_card_play(valid_actions, player, opponent, near_winning, z8_blocked)
	if not best_action.is_empty():
		return best_action

	# 4. Win check: zone 7+ and opponent zone 8 empty → invade to win
	if CardEnums.ActionType.INVADE in valid_actions:
		if player.monster_zone >= 7 and not z8_blocked:
			var invade_idx := _find_best_invade_card(player)
			if invade_idx >= 0:
				return [CardEnums.ActionType.INVADE, {"hand_index": invade_idx}]

	# 5. Gain rage (hand cycling) - discard monster cards
	if CardEnums.ActionType.GAIN_RAGE in valid_actions:
		var rage_cards := rules_engine.get_monster_cards_for_rage(player)
		if not rage_cards.is_empty():
			return [CardEnums.ActionType.GAIN_RAGE, {"hand_index": rage_cards[0]}]

	# 6. Invade based on position and playstyle
	if CardEnums.ActionType.INVADE in valid_actions:
		# Defensive playstyle skips strategic invading — only invades for the win (step 4)
		if playstyle != Playstyle.COUNTER:
			var invade_result := _decide_invade(player, opponent)
			if not invade_result.is_empty():
				return invade_result

	# 7. Pass
	return [CardEnums.ActionType.PASS, {}]


func _decide_best_card_play(valid_actions: Array, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool) -> Array:
	## Score all playable strategies and battle cards, pick the highest-value one.
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
		var playable := rules_engine.get_playable_battle_cards(player, opponent)
		for hand_idx in playable:
			var card: Dictionary = player.hand[hand_idx]
			var valid_zones := rules_engine.get_valid_zones_for_card(card, player, opponent)
			if valid_zones.is_empty():
				continue
			var score := _score_card(card, player, opponent, near_winning, z8_blocked)
			# Bonus for base CP value (higher CP cards are more impactful)
			score += card.get("counter_power", 0) / 1000
			if score > best_score:
				best_score = score
				var zone := _pick_battle_zone(valid_zones, player, opponent, card)
				best_result = [CardEnums.ActionType.PLAY_BATTLE, {"hand_index": hand_idx, "zone_index": zone}]

	return best_result


func _score_card(card: Dictionary, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool) -> int:
	var score: int = 10 # Base score: always worth playing

	# Score based on trigger map (applies to all cards with effects)
	score += _score_from_triggers(card, opponent)

	var effect := effect_handler.get_effect(card)
	if not effect:
		return score

	var tags: Array[String] = effect.get_bot_tags()
	if tags.is_empty():
		return score

	# Zone destruction is extremely valuable when near winning and z8 is blocked
	if "destroys_zone" in tags:
		score += 30
		if near_winning and z8_blocked:
			score += 50 # Could clear the path to win

	# CP boosts help with counter defense
	if "boosts_cp" in tags:
		score += 20
		if opponent.monster_zone >= 6:
			score += 15 # More valuable when opponent is close

	# Threat boosts help with winning counter checks
	if "boosts_threat" in tags:
		score += 15

	# Card draw improves future options
	if "draws_cards" in tags:
		score += 15

	# Hand disruption weakens opponent
	if "disrupts_hand" in tags:
		score += 20

	# Blocking zones restricts opponent's plays
	if "blocks_zone" in tags:
		score += 15

	# Blocking invasion prevents opponent from advancing
	if "blocks_invade" in tags:
		score += 10
		if opponent.monster_zone >= 5:
			score += 20 # Very valuable when opponent is close to winning

	# Deck search finds key cards
	if "searches_deck" in tags:
		score += 15

	# Monster advance helps push toward winning
	if "advances_monster" in tags:
		score += 20
		if near_winning:
			score += 15

	# Weakening opponent's field presence
	if "weakens_opponent" in tags:
		score += 15

	# Returning cards to deck
	if "heals_deck" in tags:
		score += 5

	# Milling own deck can fuel discard-dependent effects
	if "mill_self" in tags:
		score += 10

	# Milling opponent's deck disrupts their draws
	if "mill_opponent" in tags:
		score += 10

	# Evolution upgrades existing cards for free
	if "evolves" in tags:
		score += 20

	# Playing cards from discard builds board presence
	if "plays_from_discard" in tags:
		score += 20

	# Evolution cards gain value over time by upgrading into stronger forms
	if "evolution" in tags:
		score += 15

	# Zone/column dependent cards get a small bonus — their placement logic
	# will handle picking the right zone, but they're worth prioritizing
	if "zone_dependent" in tags:
		var preferred: Array[int] = effect.get_bot_preferred_zones()
		# Bonus if the preferred zone is relevant to the current game state
		for z in preferred:
			if z == player.monster_zone - 1 or z == player.monster_zone:
				score += 10
				break

	if "column_dependent_battle" in tags:
		# More valuable when opponent has cards on the field to mirror
		var opp_card_count: int = 0
		for z in range(8):
			if opponent.zone_has_cards(z):
				opp_card_count += 1
		if opp_card_count > 0:
			score += 10 + opp_card_count * 3

	if "column_dependent_monster" in tags:
		# Valuable when opponent's monster is on the field (always is, but zone matters)
		# Higher score when bot has zones in the same column as opponent's monster
		var opp_monster_idx: int = opponent.monster_zone - 1
		var opp_column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
		if not opp_column_zones.is_empty():
			score += 15

	# Tag synergies — bonus when this card synergizes with active/deck tags
	score += _score_synergies(tags, player, opponent)

	# Playstyle multipliers — amplify tags that align with the deck's strategy
	if playstyle == Playstyle.INVASION:
		for tag in tags:
			if tag in ["boosts_threat", "disrupts_hand", "destroys_zone", "advances_monster",
					"weakens_opponent", "mill_opponent", "column_dependent_monster"]:
				score += 10
	elif playstyle == Playstyle.COUNTER:
		for tag in tags:
			if tag in ["boosts_cp", "evolves", "evolution", "draws_cards", "searches_deck",
					"blocks_invade", "blocks_zone", "heals_deck", "column_dependent_battle"]:
				score += 10

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

	# Triggers that indicate the card does something on entry (strategies, monsters)
	if "on_enter" in triggers:
		bonus += 10

	# CP-related triggers suggest defensive value
	if "get_counter_power_modifier" in triggers or "get_field_cp_modifiers" in triggers \
			or "get_total_cp_modifier" in triggers:
		bonus += 15

	# Threat modifier suggests offensive value
	if "get_threat_level_modifier" in triggers:
		bonus += 10

	# When invading triggers suggest invade synergy
	if "on_when_invading" in triggers:
		bonus += 5

	# Phase start triggers suggest ongoing value
	if "on_phase_start" in triggers:
		bonus += 10

	# Rage-related triggers suggest combo potential
	if "on_rage_changed" in triggers or "on_opponent_rage_changed" in triggers:
		bonus += 10

	# Monster played triggers suggest synergy with rank-ups
	if "on_monster_played" in triggers:
		bonus += 5

	# Destruction replacement suggests resilience
	if "on_would_be_destroyed" in triggers or "can_be_destroyed" in triggers:
		bonus += 10

	# Engagement restriction suggests strong defensive value
	if "get_engagement_restriction" in triggers:
		bonus += 15
		if opponent.monster_zone >= 5:
			bonus += 10

	# Invasion prevention is valuable when opponent is advancing
	if "prevents_opponent_invasion" in triggers:
		bonus += 5
		if opponent.monster_zone >= 5:
			bonus += 15

	# Blocked zones restrict opponent
	if "get_blocked_opponent_zones" in triggers:
		bonus += 10

	# Strategy blocking is situationally valuable
	if "blocks_opponent_strategy_plays" in triggers:
		bonus += 10

	# Counter immunity is strong
	if "get_counter_immunity_threshold" in triggers:
		bonus += 15

	# Extra end phase advance helps win faster
	if "get_extra_end_phase_advance" in triggers:
		bonus += 15

	# Opponent field rank reduction weakens their board
	if "get_opponent_field_rank_modifier" in triggers:
		bonus += 10

	return bonus


# --- Tag synergies ---
# Each entry: [tag_on_card, synergy_tag_on_board_or_deck, bonus]
# "tag_on_card" is the tag on the card being scored.
# "synergy_tag" is checked against active board cards and deck/hand.
const TAG_SYNERGIES: Array = [
	# mill_self feeds discard pile → plays_from_discard benefits
	["mill_self", "plays_from_discard", 15],
	["plays_from_discard", "mill_self", 15],
	# heals_deck replenishes → evolution needs cards in deck to search
	["heals_deck", "evolution", 15],
	["evolution", "heals_deck", 10],
	# evolves triggers evolution → evolution cards on board benefit
	["evolves", "evolution", 20],
	["evolution", "evolves", 10],
	# destroys_zone clears path → advances_monster pushes forward
	["destroys_zone", "advances_monster", 10],
	["advances_monster", "destroys_zone", 10],
	# boosts_threat + weakens_opponent → harder to counter
	["boosts_threat", "weakens_opponent", 10],
	["weakens_opponent", "boosts_threat", 10],
	# mill_self fills discard → cards that check discard count benefit
	["mill_self", "boosts_cp", 5],
	# searches_deck + evolution → find evolution targets
	["searches_deck", "evolution", 10],
	# disrupts_hand + destroys_zone → total board control
	["disrupts_hand", "destroys_zone", 10],
	# blocks_invade + boosts_cp → lock down defense
	["blocks_invade", "boosts_cp", 10],
]


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
		var effect := effect_handler.get_effect(zone_card)
		if effect:
			for tag in effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var effect := effect_handler.get_effect(sz_card)
		if effect:
			for tag in effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1

	# Collect tags from hand (near-future potential)
	var hand_tags: Dictionary = {}
	for card in player.hand:
		var effect := effect_handler.get_effect(card)
		if effect:
			for tag in effect.get_bot_tags():
				hand_tags[tag] = hand_tags.get(tag, 0) + 1

	# Collect tags from deck (distant potential)
	var deck_tags: Dictionary = {}
	for card in player.main_deck:
		var effect := effect_handler.get_effect(card)
		if effect:
			for tag in effect.get_bot_tags():
				deck_tags[tag] = deck_tags.get(tag, 0) + 1

	var bonus: int = 0
	for synergy in TAG_SYNERGIES:
		var card_tag: String = synergy[0]
		var synergy_tag: String = synergy[1]
		var synergy_bonus: int = synergy[2]
		if card_tag in card_tags:
			if board_tags.has(synergy_tag):
				bonus += synergy_bonus           # Full bonus: on board
			elif hand_tags.has(synergy_tag):
				bonus += synergy_bonus / 2        # Half bonus: in hand
			elif deck_tags.has(synergy_tag):
				bonus += synergy_bonus / 4        # Quarter bonus: in deck
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


func _pick_battle_zone(valid_zones: Array[int], player: PlayerState, opponent: PlayerState, card: Dictionary = {}) -> int:
	# Check card effect tags for zone preferences
	var effect := effect_handler.get_effect(card) if not card.is_empty() else null
	var tags: Array[String] = effect.get_bot_tags() if effect else []

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

	# Column-dependent on monster: prefer zones in same column as opponent's monster
	if "column_dependent_monster" in tags:
		var opp_monster_idx: int = opponent.monster_zone - 1
		var opp_column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
		for z in valid_zones:
			if z in opp_column_zones and not player.zone_has_cards(z):
				return z

	# Column-dependent: prefer zones where opponent has cards (same column)
	if "column_dependent_battle" in tags:
		for z in valid_zones:
			if not player.zone_has_cards(z) and opponent.zone_has_cards(z):
				return z

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

	# Fallback: occupied zones in priority order
	for z in priority:
		if z in valid_zones:
			return z

	return valid_zones[0]


func _get_zone_priority(monster_zone: int) -> Array[int]:
	# Randomly pick one of the listed priority orders per monster zone.
	# Brackets mean "any order" — those sub-arrays get shuffled.
	# Values use 1-based zone numbers, converted to 0-indexed at the end.
	var priority: Array = []
	match monster_zone:
		1:
			# z1 => 8,7,6,5,4,3,2 or 7,8,6,5,4,3,2
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5, 4, 3, 2]
			else:
				priority = [7, 8, 6, 5, 4, 3, 2]
		2:
			# z2 => 8,7,6,5,4,3,1 or 7,8,6,5,4,3,1 or 1,8,7,6,5,4,3
			var roll := randi() % 3
			if roll == 0:
				priority = [8, 7, 6, 5, 4, 3, 1]
			elif roll == 1:
				priority = [7, 8, 6, 5, 4, 3, 1]
			else:
				priority = [1, 8, 7, 6, 5, 4, 3]
		3:
			# z3 => 8,7,6,5,4,[2,1] or 7,8,6,5,4,[2,1]
			var tail := _shuffled([2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5, 4] + tail
			else:
				priority = [7, 8, 6, 5, 4] + tail
		4:
			# z4 => 8,7,6,5,[3,2,1] or [1,2,3],8,7,6,5
			var group := _shuffled([3, 2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5] + group
			else:
				priority = group + [8, 7, 6, 5]
		5:
			# z5 => 8,[1,2,3],4,7,6 or [1,2,3],8,4,7,6
			var group := _shuffled([1, 2, 3])
			if randi() % 2 == 0:
				priority = [8] + group + [4, 7, 6]
			else:
				priority = group + [8, 4, 7, 6]
		6:
			# z6 => 8,[1,2,3,5],4,7 or [1,2,3],[8,4,5],7
			if randi() % 2 == 0:
				var group := _shuffled([1, 2, 3, 5])
				priority = [8] + group + [4, 7]
			else:
				var front := _shuffled([1, 2, 3])
				var mid := _shuffled([8, 4, 5])
				priority = front + mid + [7]
		7:
			# z7 => [1,2,3],6,5,4,8
			var group := _shuffled([1, 2, 3])
			priority = group + [6, 5, 4, 8]
		8:
			# z8 => [1,2,3],7,6,5,4
			var group := _shuffled([1, 2, 3])
			priority = group + [7, 6, 5, 4]
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

	var result: Array[int] = []
	# 1. Monster cards first (least useful in hand)
	for idx in monster_indices:
		if result.size() >= count:
			break
		result.append(idx)
	# 2. Non-playable cards (can't use them anyway)
	for idx in non_playable_indices:
		if result.size() >= count:
			break
		result.append(idx)
	# 3. Playable cards randomly (shuffle to avoid predictability)
	playable_indices.shuffle()
	for idx in playable_indices:
		if result.size() >= count:
			break
		result.append(idx)
	return result


# --- Deck search ---

func _card_sort_value(card: Dictionary) -> int:
	## Score a card for selection priority: highest CP/threat first, then lowest rank.
	## Higher return value = better pick.
	var cp: int = card.get("counter_power", 0)
	var threat: int = card.get("threat_level", 0)
	var rank: int = card.get("rank", 0)
	# Primary: highest CP or threat (whichever is larger)
	# Secondary: lowest rank (subtract rank so lower rank scores higher)
	return maxi(cp, threat) * 10 - rank


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


func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String) -> void:
	if player_id != bot_player_id:
		return
	await _delay()
	# Pick best matching card by CP/threat then lowest rank
	var best := _pick_best_card(matching_cards)
	effect_handler.resolve_deck_search(best)


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
