extends RefCounted
## Bot card, synergy, rank-up and choice scoring — method bodies moved verbatim from bot_player.gd
## (Phase 7 split); BotPlayer state/methods are reached via `_bot`.
## Weak back-reference: BotPlayer owns this helper strongly, so a strong
## ref back would form an uncollectable RefCounted cycle.

var _bot_ref: WeakRef
var _bot: BotPlayer:
	get:
		return _bot_ref.get_ref()


func _init(bot) -> void:
	_bot_ref = weakref(bot)


func _score_card(card: Dictionary, player: PlayerState, opponent: PlayerState, near_winning: bool, z8_blocked: bool) -> int:
	var score: int = _bot.config.base_play_score

	# Score based on trigger map (applies to all cards with effects)
	score += _bot._score_from_triggers(card, opponent)

	var effect := _bot.effect_handler.get_effect(card)
	if not effect:
		return score

	var tags: Array[String] = effect.get_bot_tags()
	if tags.is_empty():
		return score

	# Penalize unfulfillable triggers — deduct score for each on_* trigger
	# whose bot_can_fulfill_* returns false (the card's effect won't fully fire)
	if _bot.config.use_activation_check:
		var triggers: Array = _bot._TriggerMap.TRIGGERS.get(card.get("effect_script", ""), [])
		var has_destroy := "destroys_zone" in tags
		for trigger in triggers:
			var method: StringName = _bot._TRIGGER_FULFILL_MAP.get(trigger, &"")
			if method == &"":
				continue
			var result: bool
			if method == &"bot_can_fulfill_on_phase_start":
				result = effect.call(method, player, opponent, _bot.effect_handler)
			else:
				result = effect.call(method, player, opponent)
			if not result:
				if has_destroy and trigger == &"on_enter":
					score -= _bot.config.unfulfilled_destroy_penalty
				else:
					score -= _bot.config.unfulfilled_trigger_penalty

	# Base tag scores from config
	for tag in tags:
		score += _bot.config.tag_scores.get(tag, 0)

	# Situational tag bonuses
	for tag in tags:
		if tag in _bot.config.tag_situational_bonuses:
			var bonuses: Dictionary = _bot.config.tag_situational_bonuses[tag]
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
				score += _bot.config.zone_dependent_bonus
				break

	if _bot.config.consider_column_tags:
		if "column_dependent_battle" in tags:
			var opp_card_count: int = 0
			for z in range(8):
				if opponent.zone_has_cards(z):
					opp_card_count += 1
			if opp_card_count > 0:
				score += _bot.config.column_dependent_battle_base + opp_card_count * _bot.config.column_dependent_battle_per_card

		if "column_dependent_monster" in tags:
			var opp_monster_idx: int = opponent.monster_zone - 1
			var opp_column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
			if not opp_column_zones.is_empty():
				score += _bot.config.column_dependent_monster_bonus

	# Tag synergies — bonus when this card synergizes with active/deck tags
	if _bot.config.enable_synergies:
		score += _bot._score_synergies(tags, player, opponent)

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
				if _bot._is_valid_destroy_target(opponent, z, destroy_max_rank):
					effective_target_count += 1
		elif "column_dependent_monster" in tags:
			var opp_monster_idx: int = opponent.monster_zone - 1
			var column_zones := CardEffect.get_opponent_column_zones(opp_monster_idx)
			effective_target_count = 0
			for z in column_zones:
				if _bot._is_valid_destroy_target(opponent, z, destroy_max_rank):
					effective_target_count += 1
		elif destroy_max_rank > 0:
			effective_target_count = 0
			for z in range(8):
				if _bot._is_valid_destroy_target(opponent, z, destroy_max_rank):
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
			elif target_zone >= 6:
				# Advancing opponent to zone 6+ is dangerous — they're near winning.
				# Only acceptable if it crushes a battle card or sets up our own win.
				var crushes_card := false
				for z in range(opponent.monster_zone - 1, mini(target_zone, 8)):
					if opponent.zone_has_battle_card(z):
						crushes_card = true
						break
				var can_win := player.monster_zone >= 7 and not opponent.zone_has_battle_card(7)
				if can_win and target_zone >= 8 and opponent.zone_has_battle_card(7):
					score += 30  # Crush z8 to clear win path
				elif crushes_card:
					score += 10  # Acceptable — crushes a card
				else:
					score -= 100  # Don't advance opponent into win range without crushing
		elif tag == "advances_self":
			var max_zone: int = -1
			if effect:
				max_zone = effect.get_bot_max_advance_zone(player, opponent)
			if max_zone > 0 and player.monster_zone >= max_zone:
				score -= 100  # Already past cap — no value
		elif tag == "boosts_cp" and not _bot.can_counter_opponent():
			score += 15

	# Playstyle multipliers — amplify tags that align with the deck's strategy
	if _bot.playstyle == _bot.Playstyle.INVASION:
		for tag in tags:
			if tag in ["boosts_threat", "disrupts_hand", "destroys_zone", "advances_self",
					"advances_opponent", "weakens_opponent", "mill_opponent", "column_dependent_monster"]:
				score += _bot.config.playstyle_multiplier
	elif _bot.playstyle == _bot.Playstyle.COUNTER:
		for tag in tags:
			if tag in ["boosts_cp", "evolves", "evolution", "draws_cards", "searches_deck",
					"blocks_invade", "blocks_zone", "heals_deck", "column_dependent_battle"]:
				score += _bot.config.playstyle_multiplier

	return score


func _score_from_triggers(card: Dictionary, opponent: PlayerState) -> int:
	## Infer a score bonus from the trigger map when bot tags are not defined.
	var script_path: String = card.get("effect_script", "")
	if script_path.is_empty():
		return 0
	var triggers: Array = _bot._TriggerMap.TRIGGERS.get(script_path, [])
	if triggers.is_empty():
		return 0

	var bonus: int = 0

	# Score from trigger rules (grouped triggers — any match adds score once)
	for rule in _bot.config.trigger_score_rules:
		var trigger_names: Array = rule[0]
		var rule_score: int = rule[1]
		for t_name in trigger_names:
			if t_name in triggers:
				bonus += rule_score
				break

	# Situational trigger bonuses
	for entry in _bot.config.trigger_situational_bonuses:
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
		var zone_effect := _bot.effect_handler.get_effect(zone_card)
		if zone_effect:
			for tag in zone_effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var sz_effect := _bot.effect_handler.get_effect(sz_card)
		if sz_effect:
			for tag in sz_effect.get_bot_tags():
				board_tags[tag] = board_tags.get(tag, 0) + 1

	# Collect tags from hand (near-future potential)
	var hand_tags: Dictionary = {}
	for h_card in player.hand:
		var h_effect := _bot.effect_handler.get_effect(h_card)
		if h_effect:
			for tag in h_effect.get_bot_tags():
				hand_tags[tag] = hand_tags.get(tag, 0) + 1

	# Collect tags from deck (distant potential)
	var deck_tags: Dictionary = {}
	for d_card in player.main_deck:
		var d_effect := _bot.effect_handler.get_effect(d_card)
		if d_effect:
			for tag in d_effect.get_bot_tags():
				deck_tags[tag] = deck_tags.get(tag, 0) + 1

	var bonus: int = 0
	for synergy in _bot.config.tag_synergies:
		var card_tag: String = synergy[0]
		var synergy_tag: String = synergy[1]
		var synergy_bonus: int = synergy[2]
		if card_tag in card_tags:
			if board_tags.has(synergy_tag):
				bonus += int(synergy_bonus * _bot.config.synergy_board_multiplier)
			elif hand_tags.has(synergy_tag):
				bonus += int(synergy_bonus * _bot.config.synergy_hand_multiplier)
			elif deck_tags.has(synergy_tag):
				bonus += int(synergy_bonus * _bot.config.synergy_deck_multiplier)
	return bonus


func _score_enabler_bonus(my_idx: int, my_tags: Array, all_playable_tags: Dictionary) -> int:
	## Bonus for cards that enable synergies for other playable cards in hand.
	## If this card's tags match the synergy_tag another card needs on the board,
	## playing this card first sets up the synergy — boost its score.
	var bonus: int = 0
	for synergy in _bot.config.tag_synergies:
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


func _score_rankup_candidates(monsters: Array[Dictionary], valid_indices: Array[int]) -> int:
	## Score each rankup candidate and return the best index.
	## Scoring layers: base rank, effect tags, combo preferences.
	var player := _bot.game_state.players[_bot.bot_player_id]
	var opponent := _bot.game_state.players[1 - _bot.bot_player_id]
	var best_idx: int = valid_indices[valid_indices.size() - 1]
	var best_score: int = -999

	for idx in valid_indices:
		var monster: Dictionary = monsters[idx]
		var score: int = 0

		# Base: prefer higher rank (primary tiebreaker)
		score += monster.get("rank", 0) * 10

		# Threat level: prefer higher threat
		score += monster.get("threat_level", 0) / 1000

		# Effect tags: score useful abilities
		var effect := _bot.effect_handler.get_effect(monster)
		if effect:
			var tags: Array[String] = effect.get_bot_tags()
			# Advancing opponent is valuable when they're in z5+
			if "advances_opponent" in tags and opponent.monster_zone >= 5:
				score += 40
			# Destroying zones is valuable near endgame
			if "destroys_zone" in tags:
				score += 20
			# Threat boost scales with rage
			if "boosts_threat" in tags and player.rage >= 2:
				score += 15
			# Advancement effects when combo is active
			if "advances_self" in tags:
				score += 10

		# Combo preferences (highest priority layer)
		score += _bot._get_combo_rankup_bonus(monster, player, opponent)

		if score > best_score:
			best_score = score
			best_idx = idx

	return best_idx


func _score_choice_options(options: Array[String]) -> int:
	## Score each choice option based on keywords and game state, return best index.
	var player := _bot.game_state.players[_bot.bot_player_id]
	var opponent := _bot.game_state.players[1 - _bot.bot_player_id]

	# Zone selection pattern: "Zone N: CardName" — pick highest CP zone
	if options.size() > 0 and options[0].begins_with("Zone "):
		return _bot._pick_zone_choice(options, opponent)

	var best_idx: int = options.size() - 1  # Default: last option
	var best_score: int = -1

	for i in range(options.size()):
		var opt: String = options[i].to_lower()
		var score: int = 0

		# Self-destruction is a cost, not a payoff — only worth it if the
		# rest of the option text scores enough benefit to offset it.
		var is_self_destroy: bool = "destroy this card" in opt

		# Destruction — more valuable when opponent has lots of cards on field
		if "destroy" in opt and not is_self_destroy:
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
				if _bot.can_counter_opponent():
					score += 10  # Already ahead on CP, rage builds threat

		# Rage reduction for opponent — good when opponent has high rage,
		# worthless when they have none
		if "reduce" in opt and ("opponent" in opt or "each" in opt) and "rage" in opt:
			if opponent.rage > 0:
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

		if is_self_destroy:
			score -= 15

		if score > best_score:
			best_score = score
			best_idx = i

	return best_idx


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
		var player := _bot.game_state.players[_bot.bot_player_id]
		var active := player.current_monster
		if not active.is_empty():
			var active_rank: int = active.get("rank", 0)
			var active_traits: Array = active.get("traits", [])
			var card_rank: int = card.get("rank", 0)
			var card_traits: Array = card.get("traits", [])
			# Burst rank matching active rank is highest priority
			var has_burst_match := false
			if _bot.effect_handler != null:
				var effect := _bot.effect_handler.get_effect(card)
				if effect != null and effect.get_burst_rank() == active_rank:
					has_burst_match = true
					base += _bot.config.monster_burst_match_bonus
			# Same rank as active monster is next best for rank-up
			if not has_burst_match and card_rank == active_rank:
				base += _bot.config.monster_rank_match_bonus
			# Shared traits indicate same monster line
			for t in card_traits:
				if t in active_traits:
					base += _bot.config.monster_trait_bonus
					break
	return base


func _pick_best_card(cards: Array[Dictionary]) -> Dictionary:
	## Pick the best card from a list using _card_sort_value.
	if cards.is_empty():
		return {}
	var best: Dictionary = cards[0]
	var best_val: int = _bot._card_sort_value(best)
	for i in range(1, cards.size()):
		var val := _bot._card_sort_value(cards[i])
		if val > best_val:
			best_val = val
			best = cards[i]
	return best


func _sort_cards_by_value(cards: Array[Dictionary]) -> Array[Dictionary]:
	## Sort cards by _card_sort_value descending (best first).
	var sorted: Array[Dictionary] = cards.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _bot._card_sort_value(a) > _bot._card_sort_value(b))
	return sorted
