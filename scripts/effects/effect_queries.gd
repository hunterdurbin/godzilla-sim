class_name EffectQueries
extends EffectModule

## Read-only aggregation over active card effects: CP / threat / rank
## modifiers, blocking and restriction queries, and rule-text predicates.
## This is the narrow surface RulesEngine and the multiplayer state
## broadcast depend on; it must stay side-effect-free.


func get_burst_rank(card: Dictionary) -> int:
	## The rank this card's <Burst> allows it to be played from (-1 = no Burst).
	var effect := get_effect(card)
	return effect.get_burst_rank() if effect else -1


func is_rage_reduction_prevented(player_id: int) -> bool:
	## Check if a player's rage reduction is prevented by any active effect.
	var player := game_state.players[player_id]

	# Check monster card
	var me := get_effect(player.current_monster)
	if me and me.prevents_rage_reduction(_build_context(player_id, player.current_monster)):
		return true

	# Check battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.prevents_rage_reduction(_build_context(player_id, zone_card)):
				return true

	# Check strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se and se.prevents_rage_reduction(_build_context(player_id, sz_card)):
				return true

	return false




func can_monster_be_played_from_hand(player_id: int, card_data: Dictionary) -> bool:
	## Check if a monster card can be played via an alternate play cost.
	var effect := get_effect(card_data)
	if not effect or not has_trigger(card_data, "can_play_as_monster"):
		return false
	var ctx := _build_context(player_id, card_data)
	return effect.can_play_as_monster(ctx)




# --- Modifier queries ---

func get_counter_power_modifier(player_id: int) -> int:
	## Get total counter power modifier from all active effects (monster, zones + strategies).
	var total: int = 0
	var per_zone := get_zone_cp_modifiers(player_id)
	for mod in per_zone:
		total += mod

	total += get_monster_cp_modifier(player_id)

	# Strategy card flat CP modifiers (e.g. EBP02-017)
	var player := game_state.players[player_id]
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				total += effect.get_total_cp_modifier(_build_context(player_id, sz_card))

	return total




func get_monster_cp_modifier(player_id: int) -> int:
	## Get counter power modifier from the active monster card effect (e.g. EFC01-001).
	var player := game_state.players[player_id]
	var monster_effect := get_effect(player.current_monster)
	if monster_effect:
		return monster_effect.get_counter_power_modifier(_build_context(player_id, player.current_monster))
	return 0




func get_strategy_cp_modifiers(player_id: int) -> Array[int]:
	## Get per-strategy-slot total CP modifiers from strategy card effects.
	var player := game_state.players[player_id]
	var modifiers: Array[int] = []
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				modifiers.append(effect.get_total_cp_modifier(_build_context(player_id, sz_card)))
			else:
				modifiers.append(0)
		else:
			modifiers.append(0)
	return modifiers




func get_zone_cp_modifiers(player_id: int) -> Array[int]:
	## Get per-zone counter power modifiers from battle card effects.
	## Sum of get_zone_cp_breakdown — the per-source logic lives there.
	var breakdown := get_zone_cp_breakdown(player_id)
	var modifiers: Array[int] = []
	modifiers.resize(8)
	for i in range(8):
		modifiers[i] = ModifierBreakdown.sum(breakdown[i])
	return modifiers




func get_zone_cp_breakdown(player_id: int) -> Array:
	## Per-zone counter power modifiers with source attribution: Array of 8
	## Arrays of ModifierBreakdown entries. Entry order matters — the doubling
	## entry's amount is base CP + the running total of everything before it,
	## so sum(entries) stays exact.
	var player := game_state.players[player_id]
	var breakdown: Array = []
	breakdown.resize(8)
	for i in range(8):
		breakdown[i] = []

	# Get engagement restrictions from opponent's monster
	var opponent_id: int = 1 - player_id
	var max_restricted_rank: int = get_engagement_restriction(opponent_id)

	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(player_id, zone_card)
				var can_card_engage := effect.can_engage(ctx)
				# Check engagement restriction from opponent's monster
				if can_card_engage and max_restricted_rank >= 0:
					var card_rank: int = get_effective_field_rank(zone_card, player_id)
					if card_rank > 0 and card_rank <= max_restricted_rank:
						can_card_engage = false
				if can_card_engage:
					ModifierBreakdown.append(breakdown[i], "cp", effect.get_counter_power_modifier(ctx), zone_card, i, player_id, "z%d" % i)
				# Collect field modifiers (bonuses this card grants to other zones)
				var field_mods: Dictionary = effect.get_field_cp_modifiers(ctx)
				for zone_idx in field_mods:
					if zone_idx >= 0 and zone_idx < 8:
						ModifierBreakdown.append(breakdown[zone_idx], "cp", field_mods[zone_idx], zone_card, zone_idx, player_id, "z%d" % i)

	# Monster card field CP modifiers (e.g. EBP02-021, 041, 043)
	var monster_effect := get_effect(player.current_monster)
	if monster_effect:
		var monster_ctx := _build_context(player_id, player.current_monster)
		var monster_field_mods: Dictionary = monster_effect.get_field_cp_modifiers(monster_ctx)
		for zone_idx in monster_field_mods:
			if zone_idx >= 0 and zone_idx < 8:
				ModifierBreakdown.append(breakdown[zone_idx], "cp", monster_field_mods[zone_idx], player.current_monster, zone_idx, player_id, "monster")

	# Strategy card field CP modifiers (e.g. EBP04-082 Xilien Mothership)
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var sz_effect := get_effect(sz_card)
		if sz_effect == null:
			continue
		var sz_ctx := _build_context(player_id, sz_card)
		var sz_field_mods: Dictionary = sz_effect.get_field_cp_modifiers(sz_ctx)
		for zone_idx in sz_field_mods:
			if zone_idx >= 0 and zone_idx < 8:
				ModifierBreakdown.append(breakdown[zone_idx], "cp", sz_field_mods[zone_idx], sz_card, zone_idx, player_id, "strategy")

	# Opponent's monster CP modifiers that affect this player's zones —
	# additive bonuses first, then doubling (so the doubling sees base + all
	# other modifiers and doubles the running total, not just base CP).
	var opp_monster: Dictionary = game_state.players[opponent_id].current_monster
	var opp_monster_effect := get_effect(opp_monster)
	if opp_monster_effect:
		var opp_ctx := _build_context(opponent_id, opp_monster)
		var opp_mods: Dictionary = opp_monster_effect.get_opponent_zone_cp_modifiers(opp_ctx)
		for zone_idx in opp_mods:
			if zone_idx >= 0 and zone_idx < 8:
				ModifierBreakdown.append(breakdown[zone_idx], "cp", opp_mods[zone_idx], opp_monster, zone_idx, opponent_id, "monster")
		var doubled_zones: Array[int] = opp_monster_effect.get_opponent_doubled_zones(opp_ctx)
		for zone_idx in doubled_zones:
			if zone_idx >= 0 and zone_idx < 8:
				var base_cp: int = player.get_zone_top_card(zone_idx).get("counter_power", 0)
				# Doubling total = 2 * (base + mod). Add the existing total to
				# turn modifier into base + 2 * modifier.
				ModifierBreakdown.append(breakdown[zone_idx], "cp_double",
					base_cp + ModifierBreakdown.sum(breakdown[zone_idx]), opp_monster, zone_idx, opponent_id, "monster")

	return breakdown




func get_threat_level_modifier(player_id: int) -> int:
	## Get threat level modifier from all active effects (monster, zones, strategies).
	return ModifierBreakdown.sum(get_threat_level_breakdown(player_id))




func get_threat_level_breakdown(player_id: int) -> Array:
	## Threat level modifiers with source attribution (monster, zones, strategies).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		ModifierBreakdown.append(entries, "threat",
			me.get_threat_level_modifier(_build_context(player_id, player.current_monster)),
			player.current_monster, -1, player_id, "monster")

	# Battle cards in zones (e.g. Crystal tokens grant +1000 TL)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				ModifierBreakdown.append(entries, "threat",
					ze.get_threat_level_modifier(_build_context(player_id, zone_card)), zone_card, i, player_id, "z%d" % i)

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				ModifierBreakdown.append(entries, "threat",
					se.get_threat_level_modifier(_build_context(player_id, sz_card)), sz_card, -1, player_id, "strategy")

	return entries




func get_effective_threat_level(player_id: int) -> int:
	## Get the full effective threat level including base, rage, and all effect modifiers.
	var player := game_state.players[player_id]
	return player.get_threat_level() + get_threat_level_modifier(player_id)




func get_play_rank_modifier(player_id: int, card: Dictionary) -> int:
	## Get total play rank modifier for a card being played from hand.
	## Checks the card's own effect (self-modifier) and active strategy cards.
	return ModifierBreakdown.sum(get_play_rank_breakdown(player_id, card))




func get_play_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	## Play rank modifiers for a card being played from hand, with source
	## attribution (the card's own effect + active strategy cards).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Check the card's own effect (self-modifier, e.g. EBP02-068)
	var card_effect := get_effect(card)
	if card_effect:
		var ctx := _build_context(player_id, card)
		# If the card uses zone stacking, its rank modifier is zone-specific
		# and handled by get_zone_play_rank_modifier instead of here.
		var uses_stacking := false
		for zi in range(8):
			if card_effect.stacks_on_play(ctx, zi):
				uses_stacking = true
				break
		if not uses_stacking:
			ModifierBreakdown.append(entries, "play_rank",
				card_effect.get_play_rank_modifier_for_card(ctx, card), card, -1, player_id)

	# Check active strategy cards (e.g. EBP02-039)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				ModifierBreakdown.append(entries, "play_rank",
					effect.get_play_rank_modifier_for_card(_build_context(player_id, sz_card), card), sz_card, -1, player_id, "strategy")

	return entries




func should_stack_on_play(player_id: int, card: Dictionary, zone_index: int) -> bool:
	## Check if the card being played should stack on top of the existing zone card
	## instead of destroying it (overload).
	var effect := get_effect(card)
	if effect:
		return effect.stacks_on_play(_build_context(player_id, card), zone_index)
	return false




func get_zone_play_rank_modifier(player_id: int, card: Dictionary, zone_index: int) -> int:
	## Get zone-specific rank modifier for a card being played into a specific zone.
	var effect := get_effect(card)
	if not effect:
		return 0
	var ctx := _build_context(player_id, card)
	var zone_mod: int = effect.get_zone_play_rank_modifier(ctx, zone_index)
	# If the card stacks at this zone but no zone-specific modifier was returned,
	# fall back to the card's global self-modifier (handles stale script caches).
	if zone_mod == 0 and effect.stacks_on_play(ctx, zone_index):
		zone_mod = effect.get_play_rank_modifier_for_card(ctx, card)
	return zone_mod




func get_zone_play_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	## Zone-specific play rank modifiers for a card, one self-sourced entry
	## per zone with a nonzero modifier (covers stacks_on_play self-mods that
	## get_play_rank_breakdown intentionally skips).
	var entries: Array = []
	for zone_index in range(8):
		ModifierBreakdown.append(entries, "zone_play_rank",
			get_zone_play_rank_modifier(player_id, card, zone_index), card, zone_index, player_id)
	return entries




func is_invasion_blocked(defender_player_id: int) -> bool:
	## Check if any of the defender's battle cards prevent the opponent from invading.
	var player := game_state.players[defender_player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(defender_player_id, zone_card)
				if effect.prevents_opponent_invasion(ctx):
					return true
	return false




func get_engagement_restriction(attacker_player_id: int) -> int:
	## Get the engagement restriction from the attacker's monster and strategy effects.
	## Returns the max rank of opponent battle cards that cannot engage (-1 = no restriction).
	## If multiple sources restrict, the highest restriction wins.
	## Restriction only applies during the counter phase — the rule text excludes the
	## restricted cards' CP "during the counter phase" only. Outside it, those cards
	## report their normal counter power (e.g. EBP01-014), so effects that read power
	## in other phases aren't affected.
	if game_state.current_phase != CardEnums.GamePhase.COUNTER:
		return -1
	var player := game_state.players[attacker_player_id]
	var max_rank: int = -1

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		var r: int = me.get_engagement_restriction(_build_context(attacker_player_id, player.current_monster))
		if r > max_rank:
			max_rank = r

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				var r: int = se.get_engagement_restriction(_build_context(attacker_player_id, sz_card))
				if r > max_rank:
					max_rank = r

	return max_rank




func get_engagement_restricted_cp(defender_player_id: int) -> int:
	## Get the total base CP of the defender's cards that are restricted from engaging
	## by the attacker's monster effect. This amount should be subtracted from total CP.
	var attacker_id: int = 1 - defender_player_id
	var max_restricted_rank: int = get_engagement_restriction(attacker_id)
	if max_restricted_rank < 0:
		return 0
	var total_restricted: int = 0
	var defender := game_state.players[defender_player_id]
	for i in range(8):
		var zone_card := defender.get_zone_top_card(i)
		if not zone_card.is_empty():
			var card_rank: int = get_effective_field_rank(zone_card, defender_player_id)
			if card_rank > 0 and card_rank <= max_restricted_rank:
				total_restricted += zone_card.get("counter_power", 0)
	return total_restricted




func get_cards_that_can_engage(player_id: int) -> Array[int]:
	## Return zone indices of battle cards that can engage (not blocked by "cannot engage" effects
	## or engagement restrictions from the opponent's monster).
	## Used during counter phase to filter out restricted cards.
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var max_restricted_rank: int = get_engagement_restriction(opponent_id)
	var engageable: Array[int] = []
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			# Check engagement restriction from opponent's monster
			if max_restricted_rank >= 0:
				var card_rank: int = get_effective_field_rank(zone_card, player_id)
				if card_rank > 0 and card_rank <= max_restricted_rank:
					continue
			var effect := get_effect(zone_card)
			if effect:
				if effect.can_engage(_build_context(player_id, zone_card)):
					engageable.append(i)
			else:
				engageable.append(i)
	return engageable




func get_opponent_blocked_zones(blocker_player_id: int) -> Array[int]:
	## Collect all opponent zone indices that the blocker's cards prevent placement in.
	## Queries monster card for get_blocked_opponent_zones().
	var player := game_state.players[blocker_player_id]
	var blocked: Array[int] = []

	# Monster card
	var me := get_effect(player.current_monster)
	if me:
		var monster_blocked: Array[int] = me.get_blocked_opponent_zones(_build_context(blocker_player_id, player.current_monster))
		for z in monster_blocked:
			if z not in blocked:
				blocked.append(z)

	# Zone cards
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				var zone_blocked: Array[int] = ze.get_blocked_opponent_zones(_build_context(blocker_player_id, zone_card))
				for z in zone_blocked:
					if z not in blocked:
						blocked.append(z)

	return blocked




func get_extra_end_phase_advance(player_id: int) -> int:
	## Get extra end phase advance zones from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_extra_end_phase_advance(_build_context(player_id, player.current_monster))
	return 0




func get_invasion_advance_bonus(player_id: int, invasion_icon: int) -> int:
	## Get extra invasion advance zones from the current monster's effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_invasion_advance_bonus(_build_context(player_id, player.current_monster), invasion_icon)
	return 0




func can_play_as_monster(player_id: int, card: Dictionary) -> bool:
	## Query a monster card's alternate play cost (e.g. EBP04-033/034 "play on top of Monster X").
	## Used by ActionHandler._rank_up_monster to bridge non-overlapping traits when an
	## alternate play condition is satisfied.
	var effect := get_effect(card)
	if effect == null:
		return false
	return effect.can_play_as_monster(_build_context(player_id, card))




func _passes_own_turn_filter(card_data: Dictionary, method_name: String, watcher_player_id: int) -> bool:
	## Generic own-turn filter check for query-style virtuals
	## (can_monster_advance / can_monster_invade). Empty/missing filter = pass.
	return TriggerFilters.passes_own_turn(get_trigger_filter(card_data, method_name), game_state.current_player_id == watcher_player_id)




func is_monster_advance_blocked(player_id: int) -> bool:
	## Check if the player's monster cannot advance. Queries the monster card
	## itself plus all active strategy cards (any can override
	## `can_monster_advance` to return false). TRIGGER_FILTERS supports
	## `own_turn` for turn-gated overrides.
	var player := game_state.players[player_id]
	if not player.current_monster.is_empty() \
			and _passes_own_turn_filter(player.current_monster, "can_monster_advance", player_id):
		var effect := get_effect(player.current_monster)
		if effect and not effect.can_monster_advance(_build_context(player_id, player.current_monster)):
			return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_own_turn_filter(sz_card, "can_monster_advance", player_id):
			continue
		var se := get_effect(sz_card)
		if se and not se.can_monster_advance(_build_context(player_id, sz_card)):
			return true
	return false




func is_own_invasion_blocked(player_id: int) -> bool:
	## Check if the player's monster cannot invade. Queries the monster card
	## itself plus all active strategy cards (any can override
	## `can_monster_invade` to return false). TRIGGER_FILTERS supports
	## `own_turn` for turn-gated overrides.
	var player := game_state.players[player_id]
	if not player.current_monster.is_empty() \
			and _passes_own_turn_filter(player.current_monster, "can_monster_invade", player_id):
		var effect := get_effect(player.current_monster)
		if effect and not effect.can_monster_invade(_build_context(player_id, player.current_monster)):
			return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_own_turn_filter(sz_card, "can_monster_invade", player_id):
			continue
		var se := get_effect(sz_card)
		if se and not se.can_monster_invade(_build_context(player_id, sz_card)):
			return true
	return false




func can_replace_invasion_cost(player_id: int) -> bool:
	## Check if the current monster can replace the invasion hand-discard cost
	## with an alternative (e.g. milling from deck).
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.can_replace_invasion_cost(_build_context(player_id, player.current_monster))
	return false




func get_counter_immunity_threshold(player_id: int) -> int:
	## Get the counter immunity threshold from the player's monster and strategy cards.
	## If defender's CP <= this value, monster retreats without rank up.
	## Returns the highest threshold found across monster + strategy effects.
	var player := game_state.players[player_id]
	var best: int = 0
	var effect := get_effect(player.current_monster)
	if effect:
		best = effect.get_counter_immunity_threshold(_build_context(player_id, player.current_monster))
	# Strategy card counter immunity (e.g. EBP01-066)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty():
			var se := get_effect(sz_card)
			if se:
				var val: int = se.get_counter_immunity_threshold(_build_context(player_id, sz_card))
				if val > best:
					best = val
	return best




func is_counter_prevented(player_id: int, total_cp: int) -> bool:
	## Returns true if the invader (player_id) has any effect fully preventing
	## the counter — counter doesn't happen at all (no retreat, no rank up).
	## `total_cp` is the defender's effective CP so effects can gate prevention
	## on a CP threshold (e.g. EBP04-014: prevented only when CP <= 30000).
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect and effect.prevents_counter(_build_context(player_id, player.current_monster), total_cp):
		return true
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		var se := get_effect(sz_card)
		if se and se.prevents_counter(_build_context(player_id, sz_card), total_cp):
			return true
	return false




func are_opponent_strategy_plays_blocked(player_id: int) -> bool:
	## Check if the opponent of the given player has cards that block strategy plays.
	## player_id is the player trying to play a strategy card.
	var opponent_id: int = 1 - player_id
	var opponent := game_state.players[opponent_id]

	# Check opponent's strategy cards
	for sz_card in opponent.strategy_zones:
		if not sz_card.is_empty():
			var effect := get_effect(sz_card)
			if effect:
				if effect.blocks_opponent_strategy_plays(_build_context(opponent_id, sz_card)):
					return true

	# Check opponent's zone cards
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze:
				if ze.blocks_opponent_strategy_plays(_build_context(opponent_id, zone_card)):
					return true

	return false




func get_opponent_field_rank_modifier(player_id: int) -> int:
	## Get the field rank reduction applied to opponent's in-play battle cards.
	## Queries the player's current monster effect.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		return effect.get_opponent_field_rank_modifier(_build_context(player_id, player.current_monster))
	return 0




func is_base_strategy(card_data: Dictionary) -> bool:
	## Check if a strategy card has the <Base> keyword (12.9).
	## Base strategies are exempt from the Start Phase discard rule (7.2.3).
	var effect := get_effect(card_data)
	if effect:
		return effect.is_base_strategy()
	return false




func prevents_self_start_phase_discard(player_id: int, card_data: Dictionary) -> bool:
	## Check if a strategy card has custom anti-discard text exempting it from the
	## Start Phase discard rule (7.2.3) without being a <Base> card.
	var effect := get_effect(card_data)
	if effect:
		return effect.prevents_self_start_phase_discard(_build_context(player_id, card_data))
	return false




func can_card_be_played(player_id: int, card_data: Dictionary) -> bool:
	## Check if a card's play restriction allows it to be played.
	## Returns true if the card has no restriction or the restriction is satisfied.
	var effect := get_effect(card_data)
	if effect:
		return effect.can_be_played(_build_context(player_id, card_data))
	return true




func get_card_required_play_zones(player_id: int, card_data: Dictionary) -> Array[int]:
	## Returns the zone indices this card is restricted to, or empty if unrestricted.
	var effect := get_effect(card_data)
	if effect:
		return effect.get_required_play_zones(_build_context(player_id, card_data))
	return []




func get_effective_field_rank(card_data: Dictionary, owner_player_id: int) -> int:
	## Get the effective rank of an in-play battle card, accounting for opponent field rank modifiers.
	var base_rank: int = card_data.get("rank", 0)
	var opponent_id: int = 1 - owner_player_id
	var modifier: int = get_opponent_field_rank_modifier(opponent_id)
	return maxi(0, base_rank + modifier)




func get_zones_in_rank_range(player_id: int, min_rank: int = -1, max_rank: int = -1) -> Array[int]:
	## Return occupied zone indices whose top battle card's effective field rank
	## falls within [min_rank, max_rank]. Use -1 for either bound to leave it unbounded.
	var result: Array[int] = []
	var player := game_state.players[player_id]
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if top.is_empty():
			continue
		var rank: int = get_effective_field_rank(top, player_id)
		if min_rank >= 0 and rank < min_rank:
			continue
		if max_rank >= 0 and rank > max_rank:
			continue
		result.append(i)
	return result




func get_effective_zone_cp(player_id: int, zone_idx: int) -> int:
	## Get the effective counter power of the top battle card in a zone, including
	## per-zone CP modifiers from active effects. Returns 0 if the zone is empty.
	var top := game_state.players[player_id].get_zone_top_card(zone_idx)
	if top.is_empty():
		return 0
	var modifiers := get_zone_cp_modifiers(player_id)
	return top.get("counter_power", 0) + modifiers[zone_idx]




func get_zones_in_cp_range(player_id: int, min_cp: int = -1, max_cp: int = -1) -> Array[int]:
	## Return occupied zone indices whose top battle card's effective CP falls within
	## [min_cp, max_cp]. Use -1 for either bound to leave it unbounded. Mirrors
	## get_zones_in_rank_range; modifiers are computed once per call.
	var result: Array[int] = []
	var player := game_state.players[player_id]
	var modifiers := get_zone_cp_modifiers(player_id)
	for i in range(8):
		var top := player.get_zone_top_card(i)
		if top.is_empty():
			continue
		var cp: int = top.get("counter_power", 0) + modifiers[i]
		if min_cp >= 0 and cp < min_cp:
			continue
		if max_cp >= 0 and cp > max_cp:
			continue
		result.append(i)
	return result




func get_zone_rank_modifiers(player_id: int) -> Array:
	## Get per-zone rank modifier for display. Returns Array of 8 ints.
	## Each value is the difference between effective rank and base rank for the zone's card.
	var breakdown := get_field_rank_breakdown(player_id)
	var modifiers: Array = []
	modifiers.resize(8)
	for i in range(8):
		modifiers[i] = ModifierBreakdown.sum(breakdown[i])
	return modifiers




func get_field_rank_breakdown(player_id: int) -> Array:
	## Per-zone field rank modifiers with source attribution: Array of 8
	## Arrays of entries. Sole source is the opponent's current monster;
	## amounts are the clamped effective-minus-base delta per occupied zone.
	var breakdown: Array = []
	breakdown.resize(8)
	for i in range(8):
		breakdown[i] = []
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var rank_mod: int = get_opponent_field_rank_modifier(opponent_id)
	if rank_mod == 0:
		return breakdown
	var opp_monster: Dictionary = game_state.players[opponent_id].current_monster
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var base_rank: int = zone_card.get("rank", 0)
			var effective: int = maxi(1, base_rank + rank_mod)
			ModifierBreakdown.append(breakdown[i], "field_rank", effective - base_rank, opp_monster, i, opponent_id, "monster")
	return breakdown




# --- EBP04 new mechanism helpers ---

func is_opponent_end_phase_draw_blocked(drawing_player_id: int) -> bool:
	## Check if the drawing player is blocked from drawing during end phase.
	## Checks opponent's zone cards and monster for blocks_opponent_end_phase_draw.
	var opponent_id: int = 1 - drawing_player_id
	var opponent := game_state.players[opponent_id]
	var ctx_card := opponent.current_monster
	var effect := get_effect(ctx_card)
	if effect and effect.blocks_opponent_end_phase_draw(_build_context(opponent_id, ctx_card)):
		return true
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.blocks_opponent_end_phase_draw(_build_context(opponent_id, zone_card)):
				return true
	return false




func _passes_prevents_monster_move_filter(card_data: Dictionary, watcher_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["prevents_opponent_monster_move"] for the
	## passive-query protector. Even though this is a query (not a triggered
	## ability), authors can gate it by turn ownership or by who's causing
	## the move:
	## "own_turn": bool — gate by watcher's turn ownership.
	## "caused_by_opponent": bool — gate by `_active_effect_player_id`. true =
	##   only block when the opponent's active effect is moving the monster.
	return TriggerFilters.passes_prevents_monster_move(
		get_trigger_filter(card_data, "prevents_opponent_monster_move"),
		game_state.current_player_id == watcher_player_id, _active_effect_player_id, watcher_player_id)




func is_opponent_monster_move_blocked(target_player_id: int) -> bool:
	## Check if the target player's monster is protected from being moved by opponent effects.
	## Checks target player's strategy zones for prevents_opponent_monster_move.
	## TRIGGER_FILTERS keys: own_turn, caused_by_opponent.
	var player := game_state.players[target_player_id]
	for sz_card in player.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_prevents_monster_move_filter(sz_card, target_player_id):
			continue
		var effect := get_effect(sz_card)
		if effect and effect.prevents_opponent_monster_move(_build_context(target_player_id, sz_card)):
			return true
	return false




func is_invade1_cost_blocked(invading_player_id: int) -> bool:
	## Check if the invading player is blocked from using invade1 cards as invasion cost.
	## Checks opponent's zone cards and monster for blocks_invade1_invasion_cost.
	var opponent_id: int = 1 - invading_player_id
	var opponent := game_state.players[opponent_id]
	var effect := get_effect(opponent.current_monster)
	if effect and effect.blocks_invade1_invasion_cost(_build_context(opponent_id, opponent.current_monster)):
		return true
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var ze := get_effect(zone_card)
			if ze and ze.blocks_invade1_invasion_cost(_build_context(opponent_id, zone_card)):
				return true
	return false




func _passes_strategy_hand_rank_modifier_filter(
	card_data: Dictionary, watcher_player_id: int, target_player_id: int
) -> bool:
	## Evaluate TRIGGER_FILTERS["get_strategy_hand_rank_modifier"] for the
	## passive-query rank modifier. Authors can gate by turn ownership or by
	## whose hand the modified strategy is in:
	## "own_turn": bool — gate by watcher's turn ownership.
	## "target_is_owner": bool — gate by whose hand is being modified. true =
	##   only fire when the watcher itself owns the strategy being modified.
	return TriggerFilters.passes_strategy_hand_rank_modifier(
		get_trigger_filter(card_data, "get_strategy_hand_rank_modifier"),
		game_state.current_player_id == watcher_player_id, target_player_id == watcher_player_id)




func get_strategy_hand_rank_modifier(player_id: int, card: Dictionary) -> int:
	## Sum rank modifiers applied to a strategy card while held in player_id's hand.
	## Queries all cards from both players so effects can target owner, opponent, or both.
	## TRIGGER_FILTERS keys: own_turn, target_is_owner.
	return ModifierBreakdown.sum(get_strategy_hand_rank_breakdown(player_id, card))




func get_strategy_hand_rank_breakdown(player_id: int, card: Dictionary) -> Array:
	## Rank modifiers applied to a strategy card while held in player_id's
	## hand, with source attribution (both players' monster + zone cards).
	var entries: Array = []
	for source_id in range(2):
		var source := game_state.players[source_id]
		if not source.current_monster.is_empty() \
				and _passes_strategy_hand_rank_modifier_filter(source.current_monster, source_id, player_id):
			var effect := get_effect(source.current_monster)
			if effect:
				ModifierBreakdown.append(entries, "play_rank",
					effect.get_strategy_hand_rank_modifier(
						_build_context(source_id, source.current_monster), card, player_id),
					source.current_monster, -1, source_id, "monster")
		for i in range(8):
			var zone_card := source.get_zone_top_card(i)
			if zone_card.is_empty():
				continue
			if not _passes_strategy_hand_rank_modifier_filter(zone_card, source_id, player_id):
				continue
			var ze := get_effect(zone_card)
			if ze:
				ModifierBreakdown.append(entries, "play_rank",
					ze.get_strategy_hand_rank_modifier(
						_build_context(source_id, zone_card), card, player_id),
					zone_card, -1, source_id, "z%d" % i)
	return entries
