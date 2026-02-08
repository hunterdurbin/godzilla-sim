extends CardEffect

## EBP01-062: Godzilla vs. Destoroyah - Strategy Rank 3 (Blue)
## <Your Turn> If you have a <Destoroyah> battle card in your zones, increase your
## total counter power by +10,000.
##
## NOTE: This is a persistent strategy card effect. The CP bonus is implemented
## as a field modifier that applies to all zones proportionally.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
