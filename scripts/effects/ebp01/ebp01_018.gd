extends CardEffect

## EBP01-018: Mechagodzilla(1974) - Battle Rank 3
## <Awakening4> This card gains +3000 counter power.
## (Active if your monster card is in zone 4 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 4:
		return 3000
	return 0
