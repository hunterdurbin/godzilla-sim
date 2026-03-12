extends CardEffect
# Desghidorah (Battle R4)
# <Enter> If opponent has 3+ empty zones, Destroy 1 opponent strategy.
# If opponent has no strategy cards in play, +3000 CP.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_cp"]


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
		"Choose an opponent strategy to Destroy:")
	if idx_to_destroy >= 0:
		await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for sz in ctx.opponent.strategy_zones:
		if not sz.is_empty():
			return 0
	return 3000
