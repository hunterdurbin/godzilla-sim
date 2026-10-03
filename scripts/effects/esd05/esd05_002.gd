extends CardEffect

## ESD05-002: King Ghidorah(1991) - Monster Rank 4 (Green)
## <Enter> Send the top card of your main deck to your discard pile. When you
## do so, <Destroy> any number of your opponent's battle cards that add up to
## the discarded card's rank or less.
##
## Tested: Yes
## Known issues: None
## Edge cases: Empty deck → nothing milled, nothing destroyed.
## Rules: None
## Interactions: None
## Implementation notes: Budget = the milled card's printed rank; the pick
##   loop is EffectHandler.destroy_zones_within_rank_budget.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "mill_self"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_battle_card_zone_indices().is_empty()


func on_enter(ctx: EffectContext) -> void:
	var milled := await ctx.mill_one()
	if milled.is_empty():
		return
	await ctx.effect_handler.destroy_zones_within_rank_budget(
		ctx.owner.player_id, ctx.opponent, int(milled.get("rank", 0)))
