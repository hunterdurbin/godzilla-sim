extends CardEffect
## EBP04-038: Kamacuras - Battle Rank 3 (Red)
## If there are 2 or more other battle cards in your zones, this card gains
## +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	var count: int = 0
	for i in range(8):
		if i == my_zone:
			continue
		if ctx.owner.zone_has_cards(i):
			count += 1
	return 3000 if count >= 2 else 0
