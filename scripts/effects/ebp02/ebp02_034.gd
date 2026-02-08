extends CardEffect

## EBP02-034: Super X3 - Battle Rank 6 (Blue)
## If this card is in zone 8, this card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx == 7:  # Zone 8 = index 7
		return 3000
	return 0
