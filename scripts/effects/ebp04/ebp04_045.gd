extends CardEffect
# Manda (2004)
# When played from hand, may discard a non-blue battle card to decrease this card's
# rank by -2 for play purposes (afterwards rank is 3).
# Note: rank is currently a placeholder (0). Full rank-reduction-on-pay needs the
# real rank. Prompts the discard via apply_play_cost.


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func apply_play_cost(ctx: EffectContext, _zone_index: int) -> bool:
	await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			return CardEnums.CardColor.BLUE not in card.get("colors", []),
		"Discard a non-blue battle card to reduce this card's rank by -2 (or skip):",
		true)
	return true
