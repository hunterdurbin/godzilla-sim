extends CardEffect

## ESD02-015: Burning Godzilla's Rampage - Strategy Rank 7
## Choose 1 of your opponent's zones. <Destroy> all of your opponent's battle cards
## in that zone and zones adjacent to it.
## (For example, if a card is in zone 7, the adjacent zones are 4, 6, and 8.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	# Let player choose any opponent zone (occupied or not — adjacent zones may have cards)
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, all_zones,
		"Choose an opponent's zone to destroy (including adjacent zones):")
	if chosen < 0:
		return

	# Collect chosen zone + adjacent zones
	var zones_to_destroy: Array[int] = [chosen]
	for adj in get_adjacent_zones(chosen):
		if adj not in zones_to_destroy:
			zones_to_destroy.append(adj)

	await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
