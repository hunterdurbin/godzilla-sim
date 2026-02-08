extends CardEffect

## EBP01-066: Godzilla vs. Biollante - Strategy Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect, increase
## your monster card's <Rage> by 2.
## <Opponent's Turn> Your monster card cannot be countered by 40,000 or lower counter
## power. Instead, it only moves as though it were countered.
##
## NOTE: Counter protection mechanics require changes to resolve_counter in ActionHandler.


func on_discard_from_hand(ctx: EffectContext) -> void:
	ctx.owner.rage += 2
	ctx.owner.rage_changed.emit(ctx.owner.rage)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
