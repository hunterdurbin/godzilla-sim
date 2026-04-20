extends CardEffect
# Gigan (2004) (Battle)
# <Opponent's Turn> If non-green battle card in own zones →
# all opp strategy cards gain +2 rank (after play, return to original).
# Note: rank modifier for cards in HAND, not field — different from get_opponent_field_rank_modifier.
# This affects strategy cards in opp's hand. Not yet fully wired. Stub.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
