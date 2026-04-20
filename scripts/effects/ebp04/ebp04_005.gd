extends CardEffect
# Godzilla 2004
# <Enter> If 1 or fewer strategies in zones, search deck for Rank 1 Strategy, place + resolve.
# Each time you Destroy opp battle in same column + 3 Rank 1 strategies in discard pile,
# Destroy all opp battle cards <= rank of destroyed card.
# Note: second effect needs on_zone_card_destroyed hook. Stub for now.


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "destroys_zone"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var count: int = 0
	for sz in owner.strategy_zones:
		if not sz.is_empty():
			count += 1
	return count <= 1


func on_enter(ctx: EffectContext) -> void:
	var strat_count: int = 0
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			strat_count += 1
	if strat_count > 1:
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.STRATEGY and card.get("rank", 99) == 1,
		"Search for a Rank 1 Strategy card:")

	if found.is_empty():
		return

	# Find empty strategy zone
	var target_idx: int = -1
	for i in range(ctx.owner.strategy_zones.size()):
		if ctx.owner.strategy_zones[i].is_empty():
			target_idx = i
			break
	if target_idx < 0:
		return

	ctx.owner.strategy_zones[target_idx] = found
	ctx.owner.strategy_changed.emit()

	# Resolve the placed card's effect
	var strat_effect := ctx.effect_handler.get_effect(found)
	if strat_effect:
		var strat_ctx := EffectContext.create(ctx.game_state, ctx.owner.player_id, found, ctx.effect_handler)
		await strat_effect.on_enter(strat_ctx)
