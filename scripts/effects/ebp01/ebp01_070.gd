extends CardEffect

## EBP01-070: Baragon(1968) - Battle Rank 5 (White)
## <Enter> Look at the top card of your deck. You may send it to your discard pile
## or place it back on top of your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()

	var result: Dictionary = await ctx.effect_handler.arrange_deck_cards(
		ctx.owner.player_id, [top_card],
		tr("STR_EFF_DECK_LOOK_TOP"))

	# Put kept cards back on top
	var keep: Array = result.get("keep", [])
	for i in range(keep.size() - 1, -1, -1):
		ctx.owner.main_deck.push_front(keep[i])

	# Discard the rest
	var discard: Array = result.get("discard", [])
	for card in discard:
		ctx.owner.discard_pile.append(card)

	ctx.owner.deck_changed.emit()
	if not discard.is_empty():
		ctx.owner.discard_changed.emit()
