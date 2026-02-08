extends CardEffect

## EBP01-080: Godzilla and its son on Monster Island - Strategy Rank 6 (White)
## If your opponent has a strategy card in play, you can play this from your hand
## with its rank reduced by 2.
## While this card is in the strategy zone, your rank 5 or lower battle cards in
## zones 1-5 cannot be <Destroy> by your opponent's effects.
##
## NOTE: Rank reduction and destruction protection require system-level support.
## This effect declares the protection conditions. The rank reduction mechanic
## requires rules engine changes.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func is_base_strategy() -> bool:
	return false
