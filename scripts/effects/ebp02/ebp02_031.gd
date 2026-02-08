extends CardEffect

## EBP02-031: MBT-MB92 modified - Battle Rank 4 (Blue)
## You may have any number of this card in your deck.
## If the number of other rank 5 or lower battle cards in your zones is 2 or more,
## this card gains +3000 counter power.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	var count: int = 0
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if not top.is_empty() and top.get("id", "") != card_id and top.get("rank", 0) <= 5:
			count += 1
	if count >= 2:
		return 3000
	return 0
