extends CardEffect
# Zilla
# <Opponent's Turn> Each time one of your non-red battle cards is Destroyed →
# move this card to an area adjacent to your monster card.
# Note: needs on_ally_zone_card_destroyed hook for full accuracy.
# TODO: add trigger_ally_zone_card_destroyed in EffectHandler.


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
