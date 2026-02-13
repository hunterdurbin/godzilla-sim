extends CardEffect

## EBP02-071: Godzilla vs. King Ghidorah - Strategy Rank 4 (Green)
## Choose one of the following:
## - <Destroy> 3 of your opponent's rank 4 or lower battle cards.
## - <Awakening6> <Destroy> 2 of your opponent's rank 6 or lower battle cards.
## - <Awakening8> <Destroy> 1 of your opponent's battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	# Check Awakening8 first (strongest)
	if ctx.owner.monster_zone >= 8:
		var destroyed: Dictionary = await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(_card: Dictionary) -> bool: return true,
			"Destroy any battle card (Awakening8)? Skip for other options:")
		if not destroyed.is_empty():
			return

	# Check Awakening6 (medium)
	if ctx.owner.monster_zone >= 6:
		var r6_zones: Array[int] = []
		for i in range(8):
			var top := ctx.opponent.get_zone_top_card(i)
			if not top.is_empty() and top.get("rank", 0) <= 6:
				r6_zones.append(i)
		if not r6_zones.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, r6_zones,
				"Destroy rank 6 or lower (Awakening6)? Skip for 3x rank 4 or lower:", true)
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
				await ctx.effect_handler.destroy_zone_target(
					ctx.owner.player_id, ctx.opponent,
					func(card: Dictionary) -> bool: return card.get("rank", 0) <= 6,
					"Choose another rank 6 or lower battle card to destroy:")
				return

	# Default: destroy 3 rank 4 or lower
	for _i in range(3):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
			"Choose an opponent's rank 4 or lower battle card to destroy:")
