extends CardEffect

## EBP02-037: Destoroyah Perfect Form - Battle Rank 8 (Blue)
## <Enter> Draw 2 cards, then discard 2 cards.


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(2)
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
