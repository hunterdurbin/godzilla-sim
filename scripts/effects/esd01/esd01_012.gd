extends CardEffect

## ESD01-012: Godzilla(2023) - Battle Rank 7
## <Your Turn> When you play a monster card, you may move this card to an unoccupied zone.
## If this card is in zone 8, this card gains +3000 counter power.
## When this card is <Destroy>, place this card on the bottom of your deck instead.


func on_monster_played(ctx: EffectContext, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	# Only during your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	# Find which zone this card is in
	var current_zone_idx: int = _find_zone_of_card(ctx)
	if current_zone_idx < 0:
		return

	# Move to an unoccupied zone (pick the first available empty zone)
	var empty_zones := ctx.owner.get_empty_zone_indices()
	if not empty_zones.is_empty():
		# Move the entire stack to the target zone
		var target_zone: int = empty_zones[0]
		var stack: Array = ctx.owner.clear_zone(current_zone_idx)
		ctx.owner.zones[target_zone] = stack
		ctx.owner.zones_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# +3000 CP if in zone 8 (index 7)
	if _find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func on_revenge(ctx: EffectContext) -> void:
	_return_to_deck_bottom(ctx)


func on_crush(ctx: EffectContext) -> void:
	_return_to_deck_bottom(ctx)


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1


func _return_to_deck_bottom(ctx: EffectContext) -> void:
	var player := ctx.owner
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = player.discard_pile.pop_at(i)
			player.main_deck.append(card)
			player.deck_changed.emit()
			player.discard_changed.emit()
			return
