extends CardEffect

## EBP01-021: Rodan(1968) - Battle Rank 4
## <Enter> If this card is in the same column as your opponent's monster card, look at
## the top 2 cards of your deck, put any number on top of your deck in any order,
## and send the rest to your discard pile.


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := _find_zone_of_card(ctx)
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

	if cards.size() == 1:
		# Only 1 card — put it back
		ctx.owner.main_deck.push_front(cards[0])
		ctx.owner.deck_changed.emit()
		return

	# Let the player choose which card to put on top (the other goes to discard)
	if ctx.effect_handler.deck_search_requested.get_connections().size() > 0:
		ctx.effect_handler.deck_search_requested.emit(
			ctx.owner.player_id, cards, cards,
			"Choose a card to put on top of your deck (the other goes to discard):")
		await ctx.effect_handler._deck_search_resolved
		var selected: Dictionary = ctx.effect_handler._deck_search_result
		if not selected.is_empty():
			var sel_id: String = selected.get("id", "")
			for card in cards:
				if card.get("id") == sel_id:
					ctx.owner.main_deck.push_front(card)
				else:
					ctx.owner.discard_pile.append(card)
		else:
			for card in cards:
				ctx.owner.main_deck.push_front(card)
	else:
		# Fallback: put first on top, discard rest
		ctx.owner.main_deck.push_front(cards[0])
		ctx.owner.discard_pile.append(cards[1])

	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
