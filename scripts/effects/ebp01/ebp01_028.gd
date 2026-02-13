extends CardEffect

## EBP01-028: Godzilla vs. Mechagodzilla - Strategy Rank 2
## <Opponent's Turn> All of your opponent's rank 3 or lower battle cards cannot engage
## with your monster card. (Their counter power is not included in the total during
## the counter phase.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_engagement_restriction(ctx: EffectContext) -> int:
	# Opponent's turn only
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return -1
	return 3
