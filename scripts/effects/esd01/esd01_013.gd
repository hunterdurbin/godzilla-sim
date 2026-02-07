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
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return card.get("rank", 0) <= 6,
		"Choose an opponent's rank 6 or lower battle card to destroy:")
