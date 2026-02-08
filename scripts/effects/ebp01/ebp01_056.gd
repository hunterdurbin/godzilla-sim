extends CardEffect

## EBP01-056: Super X2 - Battle Rank 6 (Blue)
## If this card is in the same column as your opponent's monster card, this card gains
## +3000 counter power for each of your opponent's <Rage>.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := _find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return 0

	return 3000 * ctx.opponent.rage


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
