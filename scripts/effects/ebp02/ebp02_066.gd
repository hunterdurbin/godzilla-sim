extends CardEffect

## EBP02-066: King Ghidorah(1964) - Battle Rank 7 (Green)
## <Awakening6> This card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
