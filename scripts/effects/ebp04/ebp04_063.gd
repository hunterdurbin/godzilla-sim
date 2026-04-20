extends CardEffect
# Godzilla Filius
# <Revenge> Return up to 1 [Godzilla Earth] battle card from discard to hand.


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_revenge(ctx: EffectContext) -> void:
	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			return CardEnums.CardTrait.GODZILLA_EARTH in card.get("traits", []),
		"Return a Godzilla Earth battle card from your discard to your hand (or skip):")
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
