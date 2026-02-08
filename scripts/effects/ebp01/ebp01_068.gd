extends CardEffect

## EBP01-068: Manda(1968) - Battle Rank 3 (White)
## If this card is in a zone adjacent to your monster card, this card gains
## +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := _find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if zone_idx in adjacent:
		return 3000
	return 0


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
