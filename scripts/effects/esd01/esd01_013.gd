extends CardEffect

## ESD01-013: Ginza Annihilated - Strategy Rank 4
## <Your Turn> Whenever your monster card's <Rage> is increased,
## <Destroy> 1 of your opponent's rank 6 or lower battle cards.


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# Only during your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	# Only trigger when rage increases
	if new_rage <= old_rage:
		return

	# Destroy 1 of opponent's rank 6 or lower battle cards
	var opponent := ctx.opponent
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("rank", 0) <= 6:
			var stack: Array = opponent.clear_zone(i)
			opponent.discard_pile.append_array(stack)
			opponent.zones_changed.emit()
			opponent.discard_changed.emit()
			ctx.effect_handler.trigger_revenge(opponent.player_id, zone_card)
			return
