extends CardEffect
# Land Moguera (Battle R5)
# <Awakening4> <Enter> If "Star Falcon" is in your zones, choose:
# - Destroy 1 opponent strategy card, OR
# - Reduce opponent rage by 1.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 4:
		return

	# Check for Star Falcon in zones
	var has_star_falcon := false
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("name", "") == "Star Falcon":
			has_star_falcon = true
			break

	if not has_star_falcon:
		return

	# Check what options are available
	var can_destroy_strategy := false
	for sz in ctx.opponent.strategy_zones:
		if not sz.is_empty():
			can_destroy_strategy = true
			break

	var can_reduce_rage := ctx.opponent.rage > 0

	if not can_destroy_strategy and not can_reduce_rage:
		return

	# Build choice options
	var options: Array[String] = []
	var option_ids: Array[String] = []
	if can_destroy_strategy:
		options.append("Destroy 1 opponent strategy")
		option_ids.append("destroy")
	if can_reduce_rage:
		options.append("Reduce opponent rage by 1")
		option_ids.append("rage")

	var chosen_idx := await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, "Choose an effect:")
	var chosen_id: String = option_ids[chosen_idx] if chosen_idx >= 0 and chosen_idx < option_ids.size() else ""

	if chosen_id == "destroy":
		# Destroy 1 opponent strategy
		var valid_strat: Array[int] = []
		for i in range(ctx.opponent.strategy_zones.size()):
			if not ctx.opponent.strategy_zones[i].is_empty():
				valid_strat.append(i)
		if not valid_strat.is_empty():
			# Pick first occupied strategy zone (simplified - strategies use indices 0-1)
			var strat_card: Dictionary = ctx.opponent.strategy_zones[valid_strat[0]]
			ctx.opponent.strategy_zones[valid_strat[0]] = {}
			EffectHandler.banish_or_discard(ctx.opponent, [strat_card])
			ctx.opponent.strategy_zones_changed.emit()
			ctx.opponent.discard_changed.emit()
	elif chosen_id == "rage":
		var old_rage := ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
