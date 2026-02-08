extends CardEffect

## EBP01-028: Godzilla vs. Mechagodzilla - Strategy Rank 2
## <Opponent's Turn> All of your opponent's rank 3 or lower battle cards cannot engage
## with your monster card. (Their counter power is not included in the total during
## the counter phase.)
##
## NOTE: This is a continuous strategy effect. The engagement restriction requires
## system-level filtering in the counter phase. The effect_handler should check
## active strategy cards for engagement restrictions.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
