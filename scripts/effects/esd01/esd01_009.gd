extends CardEffect

## ESD01-009: Reinforcements - Battle Rank 4
## <Awakening4> This card gains +3000 counter power.
## (Active if your monster card is in zone 4 or beyond.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 4:
		return 3000
	return 0
