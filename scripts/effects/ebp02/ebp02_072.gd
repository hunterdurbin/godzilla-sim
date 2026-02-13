extends CardEffect

## EBP02-072: God of Destruction's Counterattack - Strategy Rank 5 (Green)
## <Your Turn> If you have 3 or more "Crystals" in your zones, your total
## counter power is increased by 20,000.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# <Your Turn> — only active during owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") >= 3:
		return 20000
	return 0
