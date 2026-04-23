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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func on_enter(ctx: EffectContext) -> void:
	# Check if opponent has any rank 5 or lower battle cards
	if ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 5).is_empty():
		return

	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zone_and_adjacent(
		ctx.owner.player_id, ctx.opponent, all_zones,
		"Choose a zone — rank 5 or lower cards there and in adjacent zones will be destroyed:", 5)
