extends CardEffect

## EBP02-050: Mecha-King Ghidorah - Monster Rank 4 (Green)
## <Enter> If there are 5 or more cards under this card, choose one of the following:
## - <Destroy> 3 of your opponent's rank 6 or lower battle cards.
## - Your opponent discards cards until they have 2 cards remaining in their hand.
## - Increase this card's <Rage> by 3.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_stack.size() < 5:
		return

	# Check if there are R6- cards to destroy
	var has_r6_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and top.get("rank", 0) <= 6:
			has_r6_targets = true
			break

	if has_r6_targets:
		var zones_with_targets: Array[int] = []
		for i in range(8):
			var top := ctx.opponent.get_zone_top_card(i)
			if not top.is_empty() and top.get("rank", 0) <= 6:
				zones_with_targets.append(i)
		if not zones_with_targets.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, zones_with_targets,
				"Destroy rank 6 or lower cards (skip for other options):", true)
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
				for _i in range(2):
					await ctx.effect_handler.destroy_zone_target(
						ctx.owner.player_id, ctx.opponent,
						func(card: Dictionary) -> bool: return card.get("rank", 0) <= 6,
						"Choose another rank 6 or lower battle card to destroy:")
				return

	# Option 2: discard to 2
	if ctx.opponent.hand.size() > 2:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
		return

	# Option 3: +3 rage
	var old_rage: int = ctx.owner.rage
	ctx.owner.rage += 3
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
