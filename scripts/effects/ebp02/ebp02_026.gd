extends CardEffect

## EBP02-026: Biollante Plant Beast Form - Monster Rank 3 (Blue)
## <Enter> If you have a strategy card in play, choose 1 of your opponent's zones.
## <Destroy> all of your opponent's rank 5 or lower battle cards in that zone and
## zones adjacent to it.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var has_strategy: bool = false
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			has_strategy = true
			break

	if not has_strategy:
		return

	# Check if opponent has any rank 5 or lower battle cards
	var has_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and ctx.field_rank(top, ctx.opponent.player_id) <= 5:
			has_targets = true
			break
	if not has_targets:
		return

	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zone_and_adjacent(
		ctx.owner.player_id, ctx.opponent, all_zones,
		"Choose an opponent's zone (cards there and in adjacent zones will be destroyed):", 5)
