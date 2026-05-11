extends CardEffect
## EBP04-080: Mothra Familial Bonds - Strategy Rank 2 (Blue)
## Evolve all of your rank 3 or lower battle cards with <Evolution> in your zones 1–5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolution"]


func on_enter(ctx: EffectContext) -> void:
	# Eligible: zones 1-5 (indices 0-4), battle cards with <Evolution>, field rank <= 3
	var eligible: Array[int] = []
	for i in range(5):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if not CardUtils.is_battle(zone_card):
			continue
		if zone_card.get("evolution_rank", -1) < 0:
			continue
		if ctx.field_rank(zone_card, ctx.owner.player_id) > 3:
			continue
		eligible.append(i)

	await ctx.effect_handler.evolve_zones_in_order(ctx.owner.player_id, eligible)
