extends CardEffect

## EBP02-058: Dorat - Battle Rank 2 (Green)
## <Revenge> Return up to 1 <King Ghidorah> monster card from your discard pile
## to your hand.


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.MONSTER:
				return false
			var traits: Array = card.get("traits", [])
			return CardEnums.CardTrait.KING_GHIDORAH in traits,
		"Return a King Ghidorah monster card to your hand:")

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
