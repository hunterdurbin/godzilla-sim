extends CardEffect
# Gigan (2004)
# Opp cannot discard an Invade 1 card to invade.
# <Enter> If opp monster in zones 1-5, may return 1 Gigan monster from discard to hand.
# blocks_invade1_invasion_cost is wired into ActionHandler._invade().


func blocks_invade1_invasion_cost(_ctx: EffectContext) -> bool:
	return true


func get_bot_tags() -> Array[String]:
	return ["blocks_invade"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone > 5:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.MONSTER:
				return false
			return CardEnums.CardTrait.GIGAN in card.get("traits", []),
		"Return a Gigan monster from your discard pile to your hand (or skip):")

	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
