extends CardEffect

## ESD01-003: Godzilla(2023) - Monster Rank 3
## If this card has 2 or more <Rage>, this card gains +5000 threat level.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.rage >= 2:
		return 5000
	return 0
