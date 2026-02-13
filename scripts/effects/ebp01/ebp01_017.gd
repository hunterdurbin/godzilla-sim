extends CardEffect

## EBP01-017: Kumonga(2004) - Battle Rank 2
## If this card is in zone 8, this card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if find_zone_of_card(ctx) == 7:
		return 3000
	return 0
