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


func on_enter(ctx: EffectContext) -> void:
	var milled: Array[Dictionary] = ctx.owner.mill_cards(3)
	if not milled.is_empty():
		ctx.effect_handler.log_message.emit(
			GameLog.effect_milled_cards(ctx.owner.player_id, ctx.card_data.get("id", ""), milled)
		)
		await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, milled, milled,
			"Sent to discard pile:")


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	for _i in range(3):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
			"Choose an opponent's rank 4 or lower battle card to destroy:")
