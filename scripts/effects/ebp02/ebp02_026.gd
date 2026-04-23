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


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_any_strategy_in_play()


func on_enter(ctx: EffectContext) -> void:
	var has_strategy: bool = ctx.owner.has_any_strategy_in_play()

	if not has_strategy:
		return

	# Check if opponent has any rank 5 or lower battle cards
	var has_targets: bool = not ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 5).is_empty()
	if not has_targets:
		return

	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zone_and_adjacent(
		ctx.owner.player_id, ctx.opponent, all_zones,
		"Choose an opponent's zone (cards there and in adjacent zones will be destroyed):", 5)
