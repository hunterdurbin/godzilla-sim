extends CardEffect

## EBP02-048: King Ghidorah(1991) - Monster Rank 2 (Green)
## <Enter> Send the top 3 cards of your deck to your discard pile.
## <When Invading> <Destroy> 3 of your opponent's rank 4 or lower battle cards.


func on_enter(ctx: EffectContext) -> void:
	var milled: int = 0
	for _i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		ctx.owner.discard_pile.append(ctx.owner.main_deck.pop_front())
		milled += 1

	if milled > 0:
		ctx.owner.deck_changed.emit()
		ctx.owner.discard_changed.emit()


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	for _i in range(3):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
			"Choose an opponent's rank 4 or lower battle card to destroy:")
