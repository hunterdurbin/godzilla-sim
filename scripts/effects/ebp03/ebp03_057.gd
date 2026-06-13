extends CardEffect
# Desghidorah (Battle R4)
# <Enter> If your opponent has 3 or more unoccupied zones, <Destroy> 1 of your
# opponent’s strategy cards.
# If your opponent has no strategy cards in play, this card gains +3000 counter power.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_cp"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.get_empty_zone_indices().size() >= 3


func bot_can_fulfill_counter_power(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.has_any_strategy_in_play()


func on_enter(ctx: EffectContext) -> void:
	var empty_count := ctx.opponent.get_empty_zone_indices().size()
	if empty_count < 3:
		return

	# Destroy 1 opponent strategy
	var valid_strat: Array[int] = []
	for i in range(ctx.opponent.strategy_zones.size()):
		if not ctx.opponent.strategy_zones[i].is_empty():
			valid_strat.append(i)

	if valid_strat.is_empty():
		return

	var idx_to_destroy: int = await ctx.effect_handler.select_strategy_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_strat,
		tr("STR_EFF_DESTROY_OPP_STRATEGY"))
	if idx_to_destroy >= 0:
		await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.opponent.has_any_strategy_in_play():
		return 0
	return 3000
