extends CardEffect

## EBP01-027: Hedorah(1971) - Battle Rank 8
## When playing this card from your hand, you can reduce its rank by 1 for each
## battle card in your zones. (After being played this card is rank 8.)
##
## NOTE: The rank reduction when playing is a declarative mechanic that requires
## rules engine support. The effect script provides the calculation for the system to query.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
