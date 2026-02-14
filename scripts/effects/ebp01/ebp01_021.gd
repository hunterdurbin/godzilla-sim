extends CardEffect

## EBP01-021: Rodan(1968) - Battle Rank 4
## <Enter> If this card is in the same column as your opponent's monster card, look at
## the top 2 cards of your deck, put any number on top of your deck in any order,
## and send the rest to your discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return

	var cards: Array[Dictionary] = []
	for _i in range(2):
		if ctx.owner.main_deck.is_empty():
			break
		cards.append(ctx.owner.main_deck.pop_front())

	if cards.is_empty():
		return

	var result: Dictionary = await ctx.effect_handler.arrange_deck_cards(
		ctx.owner.player_id, cards,
		"Put cards on top of deck in order, or send to discard:")

	# Put kept cards back on top (first in array = top of deck)
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
