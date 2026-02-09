extends CardEffect
# Thousand-Year Dragon King Ghidorah (Battle R8)
# If opponent has 2+ strategy cards, play with rank reduced by 2 (self-modifier).
# <Enter> Destroy 1 opponent strategy card.


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	var opp_strat_count := 0
	for sz in ctx.opponent.strategy_zones:
		if not sz.is_empty():
			opp_strat_count += 1
	if opp_strat_count >= 2:
		return -2
	return 0


func on_enter(ctx: EffectContext) -> void:
	var valid_strat: Array[int] = []
	for i in range(ctx.opponent.strategy_zones.size()):
		if not ctx.opponent.strategy_zones[i].is_empty():
			valid_strat.append(i)

	if valid_strat.is_empty():
		return

	var idx_to_destroy: int = valid_strat[0]
	if valid_strat.size() > 1:
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
