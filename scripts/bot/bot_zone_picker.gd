extends RefCounted
## Bot battle-zone and zone-target picking — method bodies moved verbatim from bot_player.gd
## (Phase 7 split); BotPlayer state/methods are reached via `_bot`.
## Weak back-reference: BotPlayer owns this helper strongly, so a strong
## ref back would form an uncollectable RefCounted cycle.

var _bot_ref: WeakRef
var _bot: BotPlayer:
	get:
		return _bot_ref.get_ref()


func _init(bot) -> void:
	_bot_ref = weakref(bot)


func _pick_battle_zone(valid_zones: Array[int], player: PlayerState, opponent: PlayerState, card: Dictionary = {}) -> int:
	# Compute effective value of each zone's existing card (base CP + effect contributions)
	var cp_modifiers := _bot.effect_handler.get_zone_cp_modifiers(player.player_id)
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
	var crush_zones := _bot._get_crush_zone_indices(2)
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
		elif _bot.can_counter_opponent():
			# All non-crush zones are occupied — crush zones are expendable since bot can counter.
			# Prefer furthest crush zone (highest index = closest to zone 8).
			crush_zones.sort()
			for i in range(crush_zones.size() - 1, -1, -1):
				var z: int = crush_zones[i]
				if z in valid_zones and not player.zone_has_cards(z):
					return z

	# Combo zone avoidance: avoid zones the combo will crush during execution
	var combo_avoid := _bot._get_combo_battle_zone_avoidance()
	if not combo_avoid.is_empty():
		var combo_safe: Array[int] = []
		for z in valid_zones:
			if z not in combo_avoid:
				combo_safe.append(z)
		if not combo_safe.is_empty():
			valid_zones = combo_safe

	# Check card effect tags for zone preferences
	var effect := _bot.effect_handler.get_effect(card) if not card.is_empty() else null
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
	if _bot.config.consider_column_tags:
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
	if not _bot.config.use_zone_priority_table:
		var empty_zones: Array[int] = []
		for z in valid_zones:
			if not player.zone_has_cards(z):
				empty_zones.append(z)
		if not empty_zones.is_empty():
			return empty_zones[randi() % empty_zones.size()]
		return valid_zones[randi() % valid_zones.size()]

	# Proactive z8 defense: start placing cards in z8 when opponent is approaching
	# z7 (at z5+), not just when they've already arrived. Gives 2-3 extra turns.
	if opponent.monster_zone >= 5:
		if 7 in valid_zones and not player.zone_has_cards(7):
			return 7

	# Build priority considering current zone AND zone+1 (monster advances at end of turn)
	var priority := _bot._get_zone_priority(player.monster_zone)
	var next_zone := mini(player.monster_zone + 1, 8)
	if next_zone != player.monster_zone:
		var next_priority := _bot._get_zone_priority(next_zone)
		# Merge: zones from next_priority that aren't already in priority get appended
		for z in next_priority:
			if z not in priority:
				priority.append(z)

	# Prefer empty zones in priority order
	for z in priority:
		if z in valid_zones and not player.zone_has_cards(z):
			return z

	# Fallback: occupied zones
	if _bot.config.overwrite_lowest_cp_when_full:
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
			shuffled_group = _bot._shuffled([2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5, 4] + shuffled_group
			else:
				priority = [7, 8, 6, 5, 4] + shuffled_group
		4:
			# z4 => 8,7,6,5,[3,2,1] or [1,2,3],8,7,6,5
			shuffled_group = _bot._shuffled([3, 2, 1])
			if randi() % 2 == 0:
				priority = [8, 7, 6, 5] + shuffled_group
			else:
				priority = shuffled_group + [8, 7, 6, 5]
		5:
			# z5 => 8,[1,2,3],4,7,6 or [1,2,3],8,4,7,6
			shuffled_group = _bot._shuffled([1, 2, 3])
			if randi() % 2 == 0:
				priority = [8] + shuffled_group + [4, 7, 6]
			else:
				priority = shuffled_group + [8, 4, 7, 6]
		6:
			# z6 => 8,[1,2,3,5],4,7 or [1,2,3],[8,4,5],7
			if randi() % 2 == 0:
				shuffled_group = _bot._shuffled([1, 2, 3, 5])
				priority = [8] + shuffled_group + [4, 7]
			else:
				shuffled_group = _bot._shuffled([1, 2, 3])
				shuffled_group2 = _bot._shuffled([8, 4, 5])
				priority = shuffled_group + shuffled_group2 + [7]
		7:
			# z7 => [1,2,3],6,5,4,8
			shuffled_group = _bot._shuffled([1, 2, 3])
			priority = shuffled_group + [6, 5, 4, 8]
		8:
			# z8 => [1,2,3],7,6,5,4
			shuffled_group = _bot._shuffled([1, 2, 3])
			priority = shuffled_group + [7, 6, 5, 4]
		_:
			priority = _bot._shuffled([1, 2, 3, 4, 5, 6, 7, 8])

	# Convert from 1-based zone numbers to 0-indexed
	var result: Array[int] = []
	for z in priority:
		result.append(z - 1)
	return result


func _get_crush_zone_indices(turns: int = 1) -> Array[int]:
	## Returns 0-indexed zone indices the bot's monster will advance through.
	## turns=1: this end of turn only. turns=2: this turn + next turn.
	var player := _bot.game_state.players[_bot.bot_player_id]
	var mz := player.monster_zone  # 1-indexed (1-8)
	if mz >= 8:
		return []
	var extra: int = 0
	if _bot.effect_handler:
		extra = _bot.effect_handler.get_extra_end_phase_advance(_bot.bot_player_id)
	var advance_per_turn: int = 1 + extra
	var total_advance: int = advance_per_turn * turns
	var crush_zones: Array[int] = []
	for i in range(1, total_advance + 1):
		var zone_num: int = mz + i
		if zone_num > 8:
			break
		crush_zones.append(zone_num - 1)  # Convert to 0-indexed
	return crush_zones


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


func _pick_opponent_zone_target(valid_zones: Array[int], player: PlayerState, opponent: PlayerState) -> int:
	## Pick the best opponent zone to destroy/target.
	var mz := player.monster_zone
	var can_win := mz == 8 or (mz == 7 and _bot.find_invade_card_with_steps(player, 2) >= 0)

	# Near win: clear the invasion path first (z8, then z7)
	if can_win:
		for z in _bot.config.destroy_zone_priority_near_win:
			if z in valid_zones:
				return z

	# Priority 1: zone 8 if it's blocking invasion and bot is in z6+
	if mz >= 6 and 7 in valid_zones and opponent.zone_has_cards(7):
		return 7

	# Priority 2: destroy the zone with highest total CP (card + adjacent cards)
	# Adjacent CP acts as tiebreaker — maximizes value for effects that also hit neighbors
	var cp_modifiers := _bot.effect_handler.get_zone_cp_modifiers(opponent.player_id)
	var max_rank: int = _bot.effect_handler.pending_destroy_max_rank
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
	var priority := _bot._get_zone_priority(mz)
	for z in priority:
		if z in valid_zones:
			return z
	return valid_zones[0]


# --- Strategy target ---


func _is_valid_destroy_target(opp: PlayerState, zone: int, max_rank: int) -> bool:
	var top := opp.get_zone_top_card(zone)
	if top.is_empty():
		return false
	if max_rank > 0 and top.get("rank", 0) > max_rank:
		return false
	return true
