extends CardEffect

## EBP01-063: Guardians Awaken - Strategy Rank 4 (Blue)
## Evolve all of your rank 4 or lower battle cards with <Evolution>.


func on_enter(ctx: EffectContext) -> void:
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("rank", 0) > 4:
			continue
		if not zone_card.has("evolution_rank"):
			continue
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, i)
