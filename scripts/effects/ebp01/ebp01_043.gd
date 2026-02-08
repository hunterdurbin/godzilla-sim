extends CardEffect

## EBP01-043: Godzilla(2000) - Monster Rank 4 (Blue)
## <Awakening4> When you successfully counter your opponent's monster card, if you have
## 5 or more monster cards in your discard pile, <Destroy> all of your opponent's
## rank 6 or lower battle cards.
##
## NOTE: The "when you successfully counter" trigger needs system-level support
## (a counter_succeeded trigger in EffectHandler). This effect is partially implemented
## through on_phase_end(COUNTER) as a workaround.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
