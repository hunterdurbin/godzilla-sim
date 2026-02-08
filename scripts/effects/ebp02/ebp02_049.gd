extends CardEffect

## EBP02-049: King Ghidorah(1991) - Monster Rank 3 (Green)
## <Enter> If there are 3 or more cards under this card, choose one of the following:
## - <Destroy> 3 of your opponent's rank 5 or lower battle cards.
## - Your opponent discards cards until they have 3 cards remaining in their hand.
## - Send the top 3 cards of your deck to your discard pile.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_stack.size() < 3:
		return

	# Offer choices via zone target — use the 3 options as "zones" hack
	# Instead, let's determine which options are viable and offer the strongest first

	# Check if there are R5- cards to destroy
	var has_r5_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and top.get("rank", 0) <= 5:
			has_r5_targets = true
			break

	# Try destroy 3 R5- first (most impactful)
	if has_r5_targets:
		var zones_with_targets: Array[int] = []
		for i in range(8):
			var top := ctx.opponent.get_zone_top_card(i)
			if not top.is_empty() and top.get("rank", 0) <= 5:
				zones_with_targets.append(i)
		if not zones_with_targets.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, zones_with_targets,
				"Destroy rank 5 or lower cards (skip for other options):", true)
			if chosen >= 0:
				# Destroy chosen + up to 2 more
				await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
				for _i in range(2):
					await ctx.effect_handler.destroy_zone_target(
						ctx.owner.player_id, ctx.opponent,
						func(card: Dictionary) -> bool: return card.get("rank", 0) <= 5,
						"Choose another rank 5 or lower battle card to destroy:")
				return

	# Option 2: discard to 3 (offer if opponent has 4+ cards)
	if ctx.opponent.hand.size() > 3:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
		return

	# Option 3: mill 3
	var milled: int = 0
	for _i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		ctx.owner.discard_pile.append(ctx.owner.main_deck.pop_front())
		milled += 1
	if milled > 0:
		ctx.owner.deck_changed.emit()
		ctx.owner.discard_changed.emit()
