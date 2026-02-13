extends CardEffect

## EBP03-071: Godzilla's Skeleton - Strategy Rank 8 (Red)
## When counting monster cards in your discard pile, treat this card as a monster card.
## Look at the top 4 cards of your deck, put any number of them on top in any order,
## send the rest to your discard pile, then draw 2 cards.
##
## Note: "counts_as_monster_in_discard" flag is set in card_data.gd.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var player := ctx.owner
	if player.main_deck.size() == 0:
		return

	# Look at top 4 cards
	var look_count: int = mini(4, player.main_deck.size())
	var top_cards: Array[Dictionary] = []
	for _i in range(look_count):
		top_cards.append(player.main_deck.pop_front())

	# Let the player choose which cards to keep on top (via select_from_cards)
	# For each card, offer choice: keep on top or discard
	var keep_on_top: Array[Dictionary] = []
	var to_discard: Array[Dictionary] = []

	for card in top_cards:
		var options: Array[String] = ["Keep on top of deck", "Send to discard pile"]
		var chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id, options,
			"Card: %s (Rank %d) — Keep on deck or discard?" % [card.get("name", "?"), card.get("rank", 0)])
		if chosen == 0:
			keep_on_top.append(card)
		else:
			to_discard.append(card)

	# Put kept cards back on top (in chosen order — last selected goes deepest)
	keep_on_top.reverse()
	for card in keep_on_top:
		player.main_deck.push_front(card)

	# Discard the rest
	for card in to_discard:
		player.discard_pile.append(card)

	player.deck_changed.emit()
	if not to_discard.is_empty():
		player.discard_changed.emit()

	# Draw 2 cards
	player.draw_cards(2)
