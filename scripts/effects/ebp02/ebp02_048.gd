extends CardEffect

## EBP02-048: King Ghidorah(1991) - Monster Rank 2 (Green)
## <Enter> Send the top 3 cards of your deck to your discard pile.
## <When Invading> <Destroy> 3 of your opponent's rank 4 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 4


func on_enter(ctx: EffectContext) -> void:
	var milled := ctx.mill(3)
	if not milled.is_empty():
		await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, milled, milled,
			tr("STR_EFF_DISCARDED_PILE"))


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	for _i in range(3):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
			tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
