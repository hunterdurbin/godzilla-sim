extends CardEffect
# Kidnapped Monsters
# Return up to 2 non-green battle cards from your discard pile to your hand.


func get_bot_tags() -> Array[String]:
	return ["recycles_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	for _i in range(2):
		var found := await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				return (card.get("card_type") == CardEnums.CardType.BATTLE and
					CardEnums.CardColor.GREEN not in card.get("colors", [])),
			"Return a non-green battle card from your discard to hand (or skip):")
		if found.is_empty():
			break
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
