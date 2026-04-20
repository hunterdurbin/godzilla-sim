extends CardEffect
# Rodan (2021)
# Unlimited copies in deck.
# <Revenge> If 5+ green battle cards in discard → return 1 Rodan battle card from discard.


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_revenge(ctx: EffectContext) -> void:
	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			green_count += 1
	if green_count < 5:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			return CardEnums.CardTrait.RODAN in card.get("traits", []),
		"Return a Rodan battle card from your discard pile to your hand (or skip):")
	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
