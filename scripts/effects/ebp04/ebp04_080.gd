extends CardEffect
# Mothra Familial Bonds
# Evolve all Rank 3 or lower battle cards with Evolution in own zones 1-5.


func get_bot_tags() -> Array[String]:
	return ["evolution"]


func on_enter(ctx: EffectContext) -> void:
	# Find all eligible zones (1-5 = indices 0-4) with evolution cards rank <= 3
	var eligible_zones: Array[int] = []
	for i in range(5):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if zone_card.get("evolution_rank", -1) < 0:
			continue
		if ctx.field_rank(zone_card, ctx.owner.player_id) > 3:
			continue
		eligible_zones.append(i)

	for zone_idx in eligible_zones:
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)
