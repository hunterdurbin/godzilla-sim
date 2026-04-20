extends CardEffect
# Gaira
# <Opponent's Turn> Each time opp returns a card from discard to hand + this in area 1 →
# return 1 card from own discard to hand.
# Note: needs trigger_card_returned_from_discard hook. Stub for now.
# TODO: add trigger_card_returned_from_discard in EffectHandler, fire from search_discard
# when used by opponent's effects.


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
