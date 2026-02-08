extends CardEffect

## EBP01-017: Kumonga(2004) - Battle Rank 2
## If this card is in zone 8, this card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
