extends CardEffect

## EBP02-017: Operation Taba - Strategy Rank 2 (Red)
## <Your Turn> If you have 4 or more battle cards in your zones,
## increase your total counter power by 5000.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_total_cp_modifier(ctx: EffectContext) -> int:
	# <Your Turn> — only active during owner's turn
	if ctx.is_opponent_turn():
		return 0
	# Count battle cards in zones
	var count: int = ctx.owner.get_occupied_zone_indices().size()
	if count >= 4:
		return 5000
	return 0
