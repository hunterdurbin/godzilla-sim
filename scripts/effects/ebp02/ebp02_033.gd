extends CardEffect

## EBP02-033: Little Godzilla - Battle Rank 5 (Blue)
## <Awakening4> This card gains +3000 counter power.
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
