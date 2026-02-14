extends CardEffect

## EBP01-038: Godzilla(1995) - Monster Rank 4 (Blue)
## <Opponent's Turn> <Awakening6> This card cannot be countered by 50,000 or lower
## counter power, instead, it only moves as though it were countered.
## (Do not play the next monster card from your monster deck.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Uses get_counter_immunity_threshold (same as EBP02-027)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_immunity_threshold(ctx: EffectContext) -> int:
	# Only active during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return 0
	# Awakening6: owner's monster must be in zone 6 or higher
	if ctx.owner.monster_zone < 6:
		return 0
	return 50000
