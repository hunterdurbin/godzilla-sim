extends CardEffect
# Rainbow Mothra R3
# <Enter> Return 1 strategy card with <Base> from your discard pile to your hand.


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.STRATEGY and card.get("is_base", false),
		"Return a Base strategy card from discard to hand:"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
