extends CardEffect
# Godzilla Jr. (Battle R7)
# If played on top of Little Godzilla, rank reduced by 2 (self-modifier).
# +5000 CP per card under this card.


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Check if any zone has a Little Godzilla on top
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if not top.is_empty() and CardEnums.CardTrait.LITTLE_GODZILLA in top.get("traits", []):
			return -2
	return 0


func stacks_on_play(ctx: EffectContext, zone_index: int) -> bool:
	var top := ctx.owner.get_zone_top_card(zone_index)
	return not top.is_empty() and CardEnums.CardTrait.LITTLE_GODZILLA in top.get("traits", [])


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var stack: Array = ctx.owner.get_zone_stack(zone_idx)
	# Cards under this card = stack size - 1 (top card is this one)
	var cards_under: int = stack.size() - 1
	return cards_under * 5000
