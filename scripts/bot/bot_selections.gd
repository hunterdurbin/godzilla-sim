extends RefCounted
## Bot discard and evolution picking — method bodies moved verbatim from bot_player.gd
## (Phase 7 split); BotPlayer state/methods are reached via `_bot`.
## Weak back-reference: BotPlayer owns this helper strongly, so a strong
## ref back would form an uncollectable RefCounted cycle.

var _bot_ref: WeakRef
var _bot: BotPlayer:
	get:
		return _bot_ref.get_ref()


func _init(bot) -> void:
	_bot_ref = weakref(bot)


func _pick_discard_indices(player: PlayerState, count: int) -> Array[int]:
	## Priority: monster cards first, then non-playable cards, then random.
	## Shin combo reserved cards are protected — discarded only as a last resort.
	var opponent := _bot.game_state.players[1 - _bot.bot_player_id]
	var combo_reserved := _bot._get_combo_reserved_indices()
	var monster_indices: Array[int] = []
	var non_playable_indices: Array[int] = []
	var playable_indices: Array[int] = []
	var protected_indices: Array[int] = []

	# Categorize hand cards
	var playable_battles := _bot.rules_engine.get_playable_battle_cards(player, opponent)
	var playable_strategies := _bot.rules_engine.get_playable_strategy_cards(player)
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
		return _bot._card_sort_value(player.hand[a]) < _bot._card_sort_value(player.hand[b]))

	var pools: Dictionary = {
		"monsters": monster_indices,
		"non_playable": non_playable_indices,
		"playable": playable_indices,
	}

	var result: Array[int] = []
	for pool_name in _bot.config.discard_priority:
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

	var player := _bot.game_state.players[_bot.bot_player_id]
	var opponent := _bot.game_state.players[1 - _bot.bot_player_id]

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
	if _bot.config.evolution_require_cp_upgrade:
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
	if not current_card.is_empty() and _bot.effect_handler:
		var current_score := _bot._score_from_triggers(current_card, opponent)
		var candidate_score := _bot._score_from_triggers(best_candidate, opponent)
		# Also factor in bot tags
		var current_effect := _bot.effect_handler.get_effect(current_card)
		var candidate_effect := _bot.effect_handler.get_effect(best_candidate)
		if current_effect:
			for tag in current_effect.get_bot_tags():
				current_score += _bot.config.tag_scores.get(tag, 0)
		if candidate_effect:
			for tag in candidate_effect.get_bot_tags():
				candidate_score += _bot.config.tag_scores.get(tag, 0)
		# Skip if current effect is worth 20+ more than candidate
		if current_score > candidate_score + 20:
			return {}

	return best_candidate
