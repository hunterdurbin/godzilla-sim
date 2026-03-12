extends CardEffect
# Godzilla Jr. (Battle R7)
# If played on top of Little Godzilla, rank reduced by 2 (self-modifier).
# +5000 CP per card under this card.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func stacks_on_play(ctx: EffectContext, zone_index: int) -> bool:
	return _zone_has_little_godzilla(ctx, zone_index)


func get_zone_play_rank_modifier(ctx: EffectContext, zone_index: int) -> int:
	if _zone_has_little_godzilla(ctx, zone_index):
		return -2
	return 0


func _zone_has_little_godzilla(ctx: EffectContext, zone_index: int) -> bool:
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
