extends CardEffect
## EBP04-005: Godzilla(2004) - Monster Rank 4 (Red)
## <Enter> If you have 1 or fewer strategy cards in play, search your deck for up to 1
## rank 1 strategy card, put it into play, shuffle your deck, then activate it.
## Whenever an opponent’s battle card in the same column as this card is <Destroy>, if
## you have 3 or more rank 1 strategy cards in your discard pile, <Destroy> all of your
## opponent’s battle cards with rank equal to or lower than the rank of the card that
## was <Destroy> in the same column as this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_opponent_zone_card_destroyed": {"column": "monster"},
}


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "destroys_zone"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.count_strategies_in_play() <= 1


func on_enter(ctx: EffectContext) -> void:
	# 1 or fewer in play (also guarantees an empty zone for the play)
	if ctx.owner.count_strategies_in_play() > 1 or not ctx.owner.has_empty_strategy_zone():
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card) and card.get("rank", 99) == 1,
		tr("STR_EFF_EBP04_005_SEARCH"))

	if found.is_empty():
		return

	# "Put it into play ... then activate it" = play it (5.9.1). search_deck
	# already shuffled the deck.
	ctx.effect_handler.play_strategy_from_effect(ctx.owner.player_id, found)


func on_opponent_zone_card_destroyed(ctx: EffectContext, destroyed_card: Dictionary, _zone_idx: int) -> void:
	var rank1_strategies_in_discard: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_strategy(card) and card.get("rank", 0) == 1:
			rank1_strategies_in_discard += 1
	if rank1_strategies_in_discard < 3:
		return
	var destroyed_rank: int = ctx.field_rank(destroyed_card, ctx.opponent.player_id)
	var targets: Array[int] = ctx.effect_handler.get_zones_in_rank_range(
		ctx.opponent.player_id, -1, destroyed_rank)
	if targets.is_empty():
		return
	await ctx.effect_handler.destroy_zones(ctx.opponent, targets)
