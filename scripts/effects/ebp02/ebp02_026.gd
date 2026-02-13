extends CardEffect

## EBP02-026: Biollante Plant Beast Form - Monster Rank 3 (Blue)
## <Enter> If you have a strategy card in play, choose 1 of your opponent's zones.
## <Destroy> all of your opponent's rank 5 or lower battle cards in that zone and
## zones adjacent to it.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var has_strategy: bool = false
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			has_strategy = true
			break

	if not has_strategy:
		return

	# Find opponent zones with cards
	var targetable: Array[int] = []
	for i in range(8):
		if not ctx.opponent.is_zone_empty(i):
			targetable.append(i)

	if targetable.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, targetable,
		"Choose an opponent's zone (cards there and in adjacent zones will be destroyed):")
	if chosen < 0:
		return

	var affected: Array[int] = [chosen]
	for adj in get_adjacent_zones(chosen):
		if adj not in affected:
			affected.append(adj)

	var zones_to_destroy: Array[int] = []
	for zi in affected:
		var zone_card := ctx.opponent.get_zone_top_card(zi)
		if not zone_card.is_empty() and zone_card.get("rank", 0) <= 5:
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
