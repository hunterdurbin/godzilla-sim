extends CardEffect
# Godzilla Jr. (Battle R7)
# If you would play this card on top of your <《Little Godzilla》> battle card, you may
# play this from your hand with its rank reduced by 2. (After being played, this card
# is rank 7.)
# This card gains +5000 counter power for each card under it.
#
# Tested: Yes
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
	return not top.is_empty() and CardUtils.has_trait(top, CardEnums.CardTrait.LITTLE_GODZILLA)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var stack: Array = ctx.owner.get_zone_stack(zone_idx)
	# Cards under this card = stack size - 1 (top card is this one)
	var cards_under: int = stack.size() - 1
	return cards_under * 5000
