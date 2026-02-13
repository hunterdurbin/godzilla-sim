extends CardEffect

## EBP01-046: MBT-MB92 - Battle Rank 3 (Blue)
## You may have any number of this card in your deck.
## <Awakening6> This card gains +3000 counter power.
## (Active if your monster card is in zone 6 or beyond.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
