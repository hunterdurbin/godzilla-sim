extends CardEffect

## EBP01-065: Godzilla vs. Destoroyah - Strategy Rank 6 (Blue)
## <Destroy> all of your opponent's battle cards in zones 1-5.


func on_enter(ctx: EffectContext) -> void:
	var zones_to_destroy: Array[int] = []
	for i in range(5):  # zones 1-5 = indices 0-4
		if not ctx.opponent.is_zone_empty(i):
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
