extends CardEffect

## EBP01-038: Godzilla(1995) - Monster Rank 4 (Blue)
## <Opponent's Turn> <Awakening6> This card cannot be countered by 50,000 or lower
## counter power, instead, it only moves as though it were countered.
## (Do not play the next monster card from your monster deck.)
##
## NOTE: Counter protection mechanics require changes to the resolve_counter logic
## in ActionHandler. This effect declares the intent but needs system support.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
