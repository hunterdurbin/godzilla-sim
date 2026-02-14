extends CardEffect

## EBP01-066: Godzilla vs. Biollante - Strategy Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect, increase
## your monster card's <Rage> by 2.
## <Opponent's Turn> Your monster card cannot be countered by 40,000 or lower counter
## power. Instead, it only moves as though it were countered.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Strategy counter immunity via get_counter_immunity_threshold


func on_discard_from_hand(ctx: EffectContext) -> void:
	ctx.owner.rage += 2
	ctx.owner.rage_changed.emit(ctx.owner.rage)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_immunity_threshold(ctx: EffectContext) -> int:
	# Only active during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return 0
	return 40000
