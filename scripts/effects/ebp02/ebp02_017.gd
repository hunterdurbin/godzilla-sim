extends CardEffect

## EBP02-017: Operation Taba - Strategy Rank 2 (Red)
## <Your Turn> If you have 4 or more battle cards in your zones,
## increase your total counter power by 5000.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# <Your Turn> — only active during owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	# Count battle cards in zones
	var count: int = 0
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			count += 1
	if count >= 4:
		return 5000
	return 0
