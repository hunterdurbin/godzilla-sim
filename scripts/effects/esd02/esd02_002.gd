extends CardEffect

## ESD02-002: Godzilla(1989) - Monster Rank 2
## <Enter> <Destroy> 1 of your opponent's rank 4 or lower battle cards.


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool:
			return card.get("rank", 0) <= 4,
		"Choose an opponent's rank 4 or lower battle card to destroy:")
