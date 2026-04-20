extends CardEffect
# Gigan (2004)
# Opp cannot discard an Invade 1 card to invade.
# <Enter> If opp monster in zones 1-5, may return 1 Gigan monster from discard to hand.
# Note: blocks_invade1_invasion_cost is a new mechanism — stub returns true.
# TODO: wire blocks_invade1_invasion_cost into ActionHandler._invade().


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
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
