extends CardEffect

## EBP01-029: Unthinkable Destruction - Strategy Rank 3
## Choose 1 of your opponent's zones. <Destroy> all of your opponent's rank 5 or lower
## battle cards in that zone and zones adjacent to it.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	# Find opponent zones that have rank 5 or lower battle cards
	var targetable_zones: Array[int] = []
	for i in range(8):
		if not ctx.opponent.is_zone_empty(i):
			targetable_zones.append(i)

	if targetable_zones.is_empty():
		return

	# Let the player choose a center zone (any occupied zone)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, targetable_zones,
		"Choose a zone center — rank 5 or lower cards there and in adjacent zones will be destroyed:")
	if chosen < 0:
		return

	# Gather the chosen zone + adjacent zones
	var affected_zones: Array[int] = [chosen]
	for adj in get_adjacent_zones(chosen):
		if adj not in affected_zones:
			affected_zones.append(adj)

	# Filter for rank 5 or lower
	var zones_to_destroy: Array[int] = []
	for zi in affected_zones:
		var zone_card := ctx.opponent.get_zone_top_card(zi)
		if not zone_card.is_empty() and zone_card.get("rank", 0) <= 5:
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
