extends CardEffect
# Land Moguera (Battle R5)
# <Awakening4> <Enter> If “Star Falcon” is in your zones, choose one:
# ・ <Destroy> 1 of your opponent’s strategy cards.
# ・Reduce your opponent’s <Rage> by 1.
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
	if not owner.is_awakening(4):
		return false
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return c.get("name", "") == "Star Falcon")


func on_enter(ctx: EffectContext) -> void:
	if not ctx.is_awakening(4):
		return

	# Check for Star Falcon in zones
	var has_star_falcon := ctx.owner.has_zone_matching(func(c: Dictionary) -> bool:
		return c.get("name", "") == "Star Falcon")

	if not has_star_falcon:
		return

	# Check what options are available
	var can_destroy_strategy := ctx.opponent.has_any_strategy_in_play()

	var can_reduce_rage := ctx.opponent_has_rage()

	if not can_destroy_strategy and not can_reduce_rage:
		return

	# Build choice options
	var options: Array[String] = []
	var option_ids: Array[String] = []
	if can_destroy_strategy:
		options.append(tr("STR_EFF_EBP03_046_CHOICE_A"))
		option_ids.append("destroy")
	if can_reduce_rage:
		options.append(tr("STR_EFF_EBP03_046_CHOICE_B"))
		option_ids.append("rage")

	var chosen_idx := await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_EFFECT"))
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
				tr("STR_EFF_DESTROY_OPP_STRATEGY"))
			if idx_to_destroy >= 0:
				await ctx.effect_handler.discard_strategy_from_zone(ctx.opponent.player_id, idx_to_destroy)
	elif chosen_id == "rage":
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
