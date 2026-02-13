extends CardEffect

## EBP01-070: Baragon(1968) - Battle Rank 5 (White)
## <Enter> Look at the top card of your deck. You may send it to your discard pile
## or place it back on top of your deck.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()

	# Use deck search UI to let player decide: selecting the card = discard it
	if ctx.effect_handler.deck_search_requested.get_connections().size() > 0:
		ctx.effect_handler.deck_search_requested.emit(
			ctx.owner.player_id, [top_card], [top_card],
			"Top card of your deck — select to discard it, or cancel to keep it on top:")
		await ctx.effect_handler._deck_search_resolved
		var selected: Dictionary = ctx.effect_handler._deck_search_result
		if not selected.is_empty():
			ctx.owner.discard_pile.append(top_card)
			ctx.owner.discard_changed.emit()
		else:
			ctx.owner.main_deck.push_front(top_card)
	else:
		# Fallback: keep on top
		ctx.owner.main_deck.push_front(top_card)

	ctx.owner.deck_changed.emit()
