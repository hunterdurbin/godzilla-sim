extends CardEffect
## EBP04-053: MOGERA - Battle Rank 7 (Blue)
## <Enter> You may choose to swap zones of any 2 battle cards in your zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func on_enter(ctx: EffectContext) -> void:
	var occupied: Array[int] = ctx.owner.get_occupied_zone_indices()
	if occupied.size() < 2:
		return

	var zone_a: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		tr("STR_EFF_SWAP_FIRST_OR_SKIP"), true)
	if zone_a < 0:
		return

	var remaining: Array[int] = occupied.filter(func(z): return z != zone_a)
	if remaining.is_empty():
		return

	var zone_b: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, remaining,
		tr("STR_EFF_SWAP_SECOND"))
	if zone_b < 0:
		return

	await ctx.effect_handler.swap_zones(ctx.owner, zone_a, zone_b)
