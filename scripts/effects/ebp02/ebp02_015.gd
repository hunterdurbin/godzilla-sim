extends CardEffect

## EBP02-015: Rodan(2004) - Battle Rank 6 (Red)
## If this card is in a zone with the same number as the zone that your opponent's
## monster card occupies, this card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	# zone_idx is 0-indexed, monster_zone is 1-indexed
	if zone_idx + 1 == ctx.opponent.monster_zone:
		return 3000
	return 0
