extends CardEffect

## EBP01-051: Orga Phase II - Battle Rank 4 (Blue)
## If you have 5 or more monster cards in your discard pile, this card gains
## +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) >= 5:
		return 3000
	return 0
