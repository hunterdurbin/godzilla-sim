extends CardEffect

## EBP01-023: Mechagodzilla(1975) - Battle Rank 5
## If your monster card has 2 or more <Rage> , this card gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.rage >= 2


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.rage >= 2:
		return 3000
	return 0
