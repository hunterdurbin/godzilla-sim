extends CardEffect

## ESD01-009: Reinforcements - Battle Rank 4
## <Awakening4> This card gains +3000 counter power.
## (Active if your monster card is in zone 4 or beyond.)
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
	return owner.is_awakening(4)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(4):
		return 3000
	return 0
