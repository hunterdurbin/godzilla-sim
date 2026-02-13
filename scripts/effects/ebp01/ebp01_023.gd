extends CardEffect

## EBP01-023: Mechagodzilla(1975) - Battle Rank 5
## If your monster card has 2 or more <Rage>, this card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.rage >= 2:
		return 3000
	return 0
