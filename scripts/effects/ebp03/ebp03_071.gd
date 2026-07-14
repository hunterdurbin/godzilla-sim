extends CardEffect

## EBP03-071: Godzilla's Skeleton - Strategy Rank 8 (Red)
## When counting monster cards in your discard pile, treat this card as a monster card
## as well.
## Look at the top 4 cards of your deck, put any number of them on top of your deck in
## any order, send the rest to your discard pile, then draw 2 cards.
##
## Note: "counts_as_monster_in_discard" flag is set in the card data (scripts/cards/sets/).
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "mill_self"]


func on_enter(ctx: EffectContext) -> void:
	var player := ctx.owner
	if player.main_deck.size() == 0:
		# Skip arrange, but still draw (triggers discard reshuffle)
		player.draw_cards(2)
		return

	# Look at top 4 cards
	var look_count: int = mini(4, player.main_deck.size())
	var top_cards: Array[Dictionary] = []
	for _i in range(look_count):
		top_cards.append(player.main_deck.pop_front())

	var result: Dictionary = await ctx.effect_handler.arrange_deck_cards(
		ctx.owner.player_id, top_cards,
		tr("STR_EFF_DECK_ARRANGE_TOP"))

	# Put kept cards back on top (first in array = top of deck)
	var keep: Array = result.get("keep", [])
	for i in range(keep.size() - 1, -1, -1):
		player.main_deck.push_front(keep[i])

	# Discard the rest
	var discard: Array = result.get("discard", [])
	for card in discard:
		player.discard_pile.append(card)

	player.deck_changed.emit()
	if not discard.is_empty():
		player.discard_changed.emit()

	# Draw 2 cards
	player.draw_cards(2)
