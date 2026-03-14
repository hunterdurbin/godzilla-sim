extends CardEffect
# Land Moguera (Battle R5)
# <Awakening4> <Enter> If "Star Falcon" is in your zones, choose:
# - Destroy 1 opponent strategy card, OR
# - Reduce opponent rage by 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	if owner.monster_zone < 4:
		return false
	for i in range(8):
		var card := owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("name", "") == "Star Falcon":
			return true
	return false


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
			var idx_to_destroy: int = await ctx.effect_handler.select_strategy_target(
				ctx.owner.player_id, ctx.opponent.player_id, valid_strat,
				"Choose an opponent strategy to Destroy:")
			if idx_to_destroy >= 0:
				await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)
	elif chosen_id == "rage":
		var old_rage := ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
