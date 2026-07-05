class_name RuleActions
extends ActionResolver

## Check-timing rule actions (10.4.3, 11.x): the crush rule (11.3, interrupt),
## illegal cards (11.4), and overloaded cards (11.5).


func resolve_check_timing(state: GameState) -> void:
	## Resolve all rule actions at a check timing (10.4.3, 11.1.2).
	## Per 11.1.2.1: interrupt rule actions (crush) resolve first.
	## Per 10.4.3.1: repeat until no more rule actions remain.
	var changed := true
	while changed:
		changed = false
		# Interrupt rule actions first (11.1.2.1): crush rule (11.3)
		if await _check_crush_for_player(state, state.current_player_id):
			changed = true
		if await _check_crush_for_player(state, 1 - state.current_player_id):
			changed = true
		# Non-interrupt rule actions
		for pid in range(2):
			if _resolve_illegal_cards(state.players[pid]):
				changed = true
			if _resolve_overloaded_cards(state.players[pid]):
				changed = true


func check_crush_rule(state: GameState, deferred_entries: Variant = null) -> void:
	## Interrupt type rule action (11.3): destroy battle cards sharing a zone with a monster.
	## Per 11.1.2.1.1: turn player's interrupt rule actions resolve first.
	## When deferred_entries is provided, crush/revenge effects are collected for later
	## standby resolution instead of triggering immediately (used during movement).
	await _check_crush_for_player(state, state.current_player_id, deferred_entries)
	await _check_crush_for_player(state, 1 - state.current_player_id, deferred_entries)


func _check_crush_for_player(state: GameState, player_id: int, deferred_entries: Variant = null) -> bool:
	## Check if this player's monster shares a zone with a battle card. Returns true if crushed.
	## When deferred_entries is provided, crush/revenge effects are collected instead of
	## triggering immediately, so movement can fully resolve first.
	var player := state.players[player_id]

	# Monsters and battle cards occupy the SAME player's zones.
	# The crush rule (11.3): if a battle card is in the same zone as the monster, destroy it.
	var monster_zone_idx: int = player.monster_zone - 1  # 0-indexed
	if monster_zone_idx >= 0 and monster_zone_idx < 8:
		if player.zone_has_cards(monster_zone_idx):
			# Crush is <Destroy> (11.3.3), so on_would_be_destroyed replacements
			# apply; a replaced card never counts as destroyed and skips
			# crush/revenge, but still fires on_leave_play below.
			var top_card := player.get_zone_top_card(monster_zone_idx)
			var replaced := false
			if effect_handler:
				replaced = effect_handler.try_destroy_replacement(player, monster_zone_idx)
			if not replaced:
				var crushed_stack: Array = player.clear_zone(monster_zone_idx)
				EffectHandler.banish_or_discard(player, crushed_stack)
				player.cards_destroyed_this_turn.append(crushed_stack[0])
				events.battle_card_crushed.emit(player_id, monster_zone_idx, crushed_stack[0])
				player.zones_changed.emit()
				player.discard_changed.emit()
			if effect_handler:
				# Linked-card cleanup (rule-agnostic) fires immediately so partner
				# cards see the removal regardless of deferred standby resolution.
				await effect_handler.trigger_leave_play(player_id, top_card, monster_zone_idx)
				if replaced:
					return true
				if deferred_entries != null:
					deferred_entries.append_array(effect_handler.collect_crush_and_revenge_entries(player_id, top_card))
				else:
					await effect_handler.trigger_crush(player_id, top_card)
					await effect_handler.trigger_revenge(player_id, top_card)
			return true
	return false


func _resolve_illegal_cards(player: PlayerState) -> bool:
	## Rule 11.4 - Illegal Cards (non-interrupt rule action).
	## Strategy cards in zones that are not stacked under a battle/monster card → discard.
	## Non-strategy cards in strategy zones → discard.
	var changed := false

	# Check zones: strategy cards not stacked under another card are illegal
	for i in range(8):
		if player.is_zone_empty(i):
			continue
		var top_card := player.get_zone_top_card(i)
		if top_card.get("card_type") == CardEnums.CardType.STRATEGY:
			var stack: Array = player.clear_zone(i)
			EffectHandler.banish_or_discard(player, stack)
			changed = true

	# Check strategy zones: non-strategy cards are illegal
	for i in range(2):
		if player.strategy_zones[i].is_empty():
			continue
		if player.strategy_zones[i].get("card_type") != CardEnums.CardType.STRATEGY:
			EffectHandler.banish_or_discard(player, [player.strategy_zones[i]])
			player.strategy_zones[i] = {}
			changed = true

	if changed:
		player.zones_changed.emit()
		player.strategy_zones_changed.emit()
		player.discard_changed.emit()
	return changed


func _resolve_overloaded_cards(_player: PlayerState) -> bool:
	## Rule 11.5 - Overloaded Cards (non-interrupt rule action).
	## If any zone has multiple battle cards not in a stack, or any strategy zone has
	## multiple strategy cards, keep the last placed and destroy the rest.
	## In practice: our zones use stacks (single Array per zone) and strategy zones hold
	## single cards, so this can only occur if a card effect places cards irregularly.
	## Currently a no-op safety check for future expansion.
	return false
