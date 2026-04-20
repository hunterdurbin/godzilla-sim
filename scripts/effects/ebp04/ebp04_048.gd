extends CardEffect
# Little Godzilla
# Your in-play strategy cards cannot be Destroyed by opponent's effects.


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, _zone_idx: int) -> bool:
	# Protects strategy cards in strategy zones from opponent destruction effects
	# Note: this is called from strategy zone destruction checks, not zone_idx
	return card_data.get("card_type") == CardEnums.CardType.STRATEGY
