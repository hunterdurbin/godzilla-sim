extends CardEffect

## EBP02-061: Godzilla(1972) - Battle Rank 4 (Green)
## If this card is in zone 8, this card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx == 7:
		return 3000
	return 0
