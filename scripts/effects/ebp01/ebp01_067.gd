extends CardEffect

## EBP01-067: Gorosaurus - Battle Rank 2 (White)
## <Awakening4> This card gains +3000 counter power.
## (Active if your monster card is in zone 4 or beyond.)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 4:
		return 3000
	return 0
