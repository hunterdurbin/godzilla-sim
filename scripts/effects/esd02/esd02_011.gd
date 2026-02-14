extends CardEffect

## ESD02-011: Battra(imago) - Battle Rank 6
## <Awakening6> This card gains +3000 counter power.
## (Active if your monster card is in zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
