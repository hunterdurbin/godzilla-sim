extends RefCounted
## Bot invasion decision-making — method bodies moved verbatim from bot_player.gd
## (Phase 7 split); BotPlayer state/methods are reached via `_bot`.
## Weak back-reference: BotPlayer owns this helper strongly, so a strong
## ref back would form an uncollectable RefCounted cycle.

var _bot_ref: WeakRef
var _bot: BotPlayer:
	get:
		return _bot_ref.get_ref()


func _init(bot) -> void:
	_bot_ref = weakref(bot)


func _decide_invade(player: PlayerState, opponent: PlayerState) -> Array:
	var invade_cards := _bot.rules_engine.get_discardable_cards_for_invade(player, opponent)
	if invade_cards.is_empty():
		return []

	# Skip the discard-only cycle invade — bot shouldn't burn its invade just to
	# cycle a card when no zones can be crossed. The rules engine does allow it
	# (a legal hand-cycle: cost paid, no advancement, no movement triggers), so
	# this could become an opportunistic play — e.g. dumping a dead invade card
	# when the bot would otherwise PASS — but is deliberately skipped for now.
	if player.monster_zone >= 8 and opponent.zone_has_battle_card(7):
		return []

	var mz := player.monster_zone
	var exclude := _bot._get_combo_invasion_excludes()

	# If opponent is in z7/z8 and bot can't win this turn, don't invade — focus on defense.
	# Exception: counter-bait — if combo has counter-retreat path, invade to GET countered.
	if opponent.monster_zone >= 7:
		var combo_cr: bool = _bot._active_combo_plan.get("counter_retreat_path", false)
		if not combo_cr:
			if mz < 7:
				return []
			if mz == 7 and opponent.zone_has_battle_card(7):
				return []

	# Don't advance to z7/z8 unless bot can expect to gain rage >= 2
	# (rage gain ≈ number of monster cards in hand)
	var monsters_in_hand := _bot._count_monster_cards_in_hand(player)

	# Combo invasion preference — target specific zones for combo setup
	var combo_pref := _bot._get_combo_invasion_preference()
	var combo_target: int = combo_pref.get("target_zone", -1)
	var combo_max: int = combo_pref.get("max_zone", -1)
	var combo_steps: int = combo_pref.get("preferred_steps", 0)

	# If combo has a target zone, try to reach it
	if combo_target > 0 and mz < combo_target:
		var steps_needed: int = combo_target - mz
		if combo_steps > 0:
			var idx := _bot.find_invade_card_with_steps(player, combo_steps, exclude)
			if idx >= 0 and mz + player.hand[idx].get("invasion_icon", 0) <= (combo_max if combo_max > 0 else 99):
				if not _bot._invasion_blocked_by_rage(player, idx, monsters_in_hand):
					return [CardEnums.ActionType.INVADE, {"hand_index": idx}]
		# Try exact steps to reach target
		if steps_needed <= 2:
			var idx := _bot.find_invade_card_with_steps(player, steps_needed, exclude)
			if idx >= 0:
				if not _bot._invasion_blocked_by_rage(player, idx, monsters_in_hand):
					return [CardEnums.ActionType.INVADE, {"hand_index": idx}]

	var inv_idx: int = -1

	if _bot.playstyle == _bot.Playstyle.INVASION:
		# Aggressive: invade at any zone, prefer 2-step then any
		inv_idx = _bot.find_invade_card_with_steps(player, 2, exclude)
		if inv_idx < 0:
			inv_idx = _bot._find_best_invade_card(player, exclude)
		# Respect combo max_zone: don't overshoot
		if inv_idx >= 0 and combo_max > 0:
			var would_reach: int = mz + player.hand[inv_idx].get("invasion_icon", 0)
			if would_reach > combo_max:
				inv_idx = -1
		if inv_idx >= 0:
			if not _bot._invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]
	else:
		# Balanced: conservative invade path
		# Zone 6 → z7 for win setup
		if mz == 6:
			inv_idx = _bot.find_invade_card_with_steps(player, 1, exclude)
			if inv_idx >= 0 and not _bot._invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]
		# z1→z3 (2-step), z3→z4 (1 or 2-step), z4→z6 (2-step)
		if mz == 1 or mz == 4:
			inv_idx = _bot.find_invade_card_with_steps(player, 2, exclude)
		elif mz == 3:
			inv_idx = _bot.find_invade_card_with_steps(player, 1, exclude)
			if inv_idx < 0:
				inv_idx = _bot.find_invade_card_with_steps(player, 2, exclude)
		# z7+: invade aggressively
		elif mz >= 7:
			inv_idx = _bot._find_best_invade_card(player, exclude)
		# Respect combo max_zone: don't overshoot
		if inv_idx >= 0 and combo_max > 0:
			var would_reach: int = mz + player.hand[inv_idx].get("invasion_icon", 0)
			if would_reach > combo_max:
				inv_idx = -1
		if inv_idx >= 0:
			if not _bot._invasion_blocked_by_rage(player, inv_idx, monsters_in_hand):
				return [CardEnums.ActionType.INVADE, {"hand_index": inv_idx}]

	return []


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


func _find_best_invade_card(player: PlayerState, exclude: Array = []) -> int:
	# Prefer 2-step invasion cards, then 1-step
	var block1 := _bot._is_invade1_cost_blocked(player)
	var best_idx: int = -1
	var best_icon: int = 0
	for i in range(player.hand.size()):
		if i in exclude:
			continue
		var icon: int = player.hand[i].get("invasion_icon", 0)
		# Invade 1 cards are unusable while the opponent blocks them as cost
		# (e.g. EBP04-029 Gigan R3) — picking one would just cancel and re-loop.
		if block1 and icon == 1:
			continue
		if icon > best_icon:
			best_icon = icon
			best_idx = i
	return best_idx


func _is_invade1_cost_blocked(player: PlayerState) -> bool:
	## True when the opponent prevents this player from spending Invade 1 cards as
	## invasion cost (EBP04-029 Gigan R3). The bot must treat invasion_icon == 1
	## cards as non-invadable, or it loops forever trying a move ActionHandler
	## immediately cancels.
	return _bot.effect_handler != null and _bot.effect_handler.is_invade1_cost_blocked(player.player_id)


func _is_last_two_step_card(player: PlayerState, hand_idx: int) -> bool:
	## Returns true if this is the only 2-step invasion card in hand.
	if not _bot._combos.is_empty() and player.hand[hand_idx].get("invasion_icon", 0) >= 2:
		var count: int = 0
		for card in player.hand:
			if card.get("invasion_icon", 0) >= 2:
				count += 1
		return count <= 1
	return false


# --- Zone target ---


func find_invade_card_with_steps(player: PlayerState, steps: int, exclude: Array = []) -> int:
	var block1 := _bot._is_invade1_cost_blocked(player)
	for i in range(player.hand.size()):
		if i in exclude:
			continue
		var icon: int = player.hand[i].get("invasion_icon", 0)
		# Skip Invade 1 cards when the opponent blocks them as invasion cost — they
		# can't actually be played, so returning one just loops (EBP04-029 Gigan R3).
		if block1 and icon == 1:
			continue
		if icon >= steps:
			return i
	return -1


# --- Confirmation ---
