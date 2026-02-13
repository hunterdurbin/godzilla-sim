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

	var idx_to_destroy: int = valid_strat[0]
	var strat_options: Array[Dictionary] = []
	for si in valid_strat:
		strat_options.append(ctx.opponent.strategy_zones[si])
	var chosen := await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, strat_options, strat_options,
		"Choose an opponent strategy to Destroy:")
	if not chosen.is_empty():
		for si in valid_strat:
			if ctx.opponent.strategy_zones[si].get("id") == chosen.get("id"):
				idx_to_destroy = si
				break

	var strat_card: Dictionary = ctx.opponent.strategy_zones[idx_to_destroy]
	ctx.opponent.strategy_zones[idx_to_destroy] = {}
	EffectHandler.banish_or_discard(ctx.opponent, [strat_card])
	ctx.opponent.strategy_zones_changed.emit()
	ctx.opponent.discard_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for sz in ctx.opponent.strategy_zones:
		if not sz.is_empty():
			return 0
	return 3000
