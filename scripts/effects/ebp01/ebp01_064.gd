extends CardEffect

## EBP01-064: Godzilla vs. Megaguirus - Strategy Rank 5 (Blue)
## Choose one of the following:
## - <Destroy> 1 of your opponent's rank 4 or lower battle cards.
## - If you have 4 or more battle cards in your zones, choose 1 of your opponent's
##   zones and <Destroy> all battle cards in that zone and zones adjacent to it.


func on_enter(ctx: EffectContext) -> void:
	var battle_count: int = 0
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			battle_count += 1

	if battle_count >= 4:
		# Player can choose either option — offer the stronger option via zone target
		# If they skip zone selection, fall through to option 1
		var targetable_zones: Array[int] = []
		for i in range(8):
			if not ctx.opponent.is_zone_empty(i):
				targetable_zones.append(i)

		if not targetable_zones.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, targetable_zones,
				"Choose a zone — all cards there and in adjacent zones will be destroyed (or skip for single destroy):",
				true)

			if chosen >= 0:
				var affected_zones: Array[int] = [chosen]
				for adj in get_adjacent_zones(chosen):
					if adj not in affected_zones:
						affected_zones.append(adj)
				var zones_to_destroy: Array[int] = []
				for zi in affected_zones:
					if not ctx.opponent.is_zone_empty(zi):
						zones_to_destroy.append(zi)
				if not zones_to_destroy.is_empty():
					await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
				return

	# Option 1: Destroy 1 rank 4 or lower
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
		"Choose an opponent's rank 4 or lower battle card to destroy:")
