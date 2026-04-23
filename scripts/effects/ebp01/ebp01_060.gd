extends CardEffect

## EBP01-060: Destoroyah Perfect Form - Battle Rank 8 (Blue)
## <Enter> If this card was played through evolution, choose up to 1 strategy card
## named "Godzilla vs. Destoroyah" in your discard pile.
## If you have 1 or fewer strategy cards in play, play and activate the chosen card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	if not ctx.card_data.get("played_through_evolution", false):
		return

	# Count active strategy cards
	if ctx.owner.count_strategies_in_play() > 1:
		return

	# Search discard for "Godzilla vs. Destoroyah" strategy
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card) \
				and card.get("name", "") == "Godzilla vs. Destoroyah",
		"Choose a 'Godzilla vs. Destoroyah' strategy card from your discard pile:"
	)
	if selected.is_empty():
		return

	# Play the strategy card (regardless of rank)
	var sz_index: int = ctx.owner.get_first_empty_strategy_zone_index()
	if sz_index < 0:
		return

	ctx.owner.strategy_zones[sz_index] = selected
	ctx.owner.strategy_zone_turn_placed[sz_index] = ctx.game_state.turn_number
	ctx.owner.strategy_zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected, true)
