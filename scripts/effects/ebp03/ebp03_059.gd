extends CardEffect
# Cretaceous King Ghidorah(1998) (Battle R5)
# <Revenge> Return up to 1 King Ghidorah monster card from discard to hand.


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.MONSTER \
			and CardEnums.CardTrait.KING_GHIDORAH in card.get("traits", []),
		"Return a King Ghidorah monster from discard to hand (or skip):"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
