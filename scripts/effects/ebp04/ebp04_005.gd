extends CardEffect
## EBP04-005: Godzilla 2004 - Monster Rank 4 (Red)
## <Enter> If you have 1 or fewer strategy cards in your strategy zones, search
## your deck for 1 Rank 1 Strategy card, reveal it and place it in your strategy
## zones, shuffle your deck, and resolve the placed card's effect.
## Every time you <Destroy> an opponent's battle card in the same column as this,
## if you have 3 or more Rank 1 strategy cards in your discard pile, <Destroy>
## all of your opponent's battle cards equal to or less than the Rank of the
## battle card you <Destroy>.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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

	var target_idx: int = -1
	for i in range(ctx.owner.strategy_zones.size()):
		if ctx.owner.strategy_zones[i].is_empty():
			target_idx = i
			break
	if target_idx < 0:
		return

	ctx.owner.strategy_zones[target_idx] = found
	ctx.owner.strategy_changed.emit()

	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, found)


func on_opponent_zone_card_destroyed(ctx: EffectContext, destroyed_card: Dictionary, zone_idx: int) -> void:
	var my_zone_idx: int = ctx.owner.monster_zone - 1
	if my_zone_idx < 0:
		return
	if zone_idx not in get_opponent_column_zones(my_zone_idx):
		return
	var rank1_in_discard: int = 0
	for card in ctx.owner.discard:
		if ctx.field_rank(card, ctx.owner.player_id) == 1:
			rank1_in_discard += 1
	if rank1_in_discard < 3:
		return
	var destroyed_rank: int = ctx.field_rank(destroyed_card, ctx.opponent.player_id)
	var targets: Array[int] = []
	for i in range(8):
		var card := ctx.opponent.get_zone_top_card(i)
		if not card.is_empty() and ctx.field_rank(card, ctx.opponent.player_id) <= destroyed_rank:
			targets.append(i)
	if targets.is_empty():
		return
	await ctx.effect_handler.destroy_zones(ctx.opponent, targets)
