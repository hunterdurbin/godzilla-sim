extends CardEffect
# Kaiser Ghidorah (Battle)
# <Your Turn> If no strategies in play → strategy cards in hand gain -1 rank per color in discard.
# Note: get_strategy_hand_rank_modifier is a new mechanism not yet wired into RulesEngine.
# TODO: wire into RulesEngine.get_effective_rank_for_play().


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
