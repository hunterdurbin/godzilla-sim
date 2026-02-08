extends CardEffect

## EBP01-041: Godzilla(2000) - Monster Rank 1 (Blue)
## <When Invading> <Destroy> 1 of your opponent's rank 4 or lower battle cards.


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
		"Choose an opponent's rank 4 or lower battle card to destroy:")
