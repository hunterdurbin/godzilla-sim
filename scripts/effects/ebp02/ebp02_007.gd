extends CardEffect

## EBP02-007: Godzilla(2016) 4th Form - Monster Rank 4 (Red)
## <Burst3>
## <Enter> You may discard 1 strategy card from your hand. If you do, reveal the top 5
## cards of your deck, add 1 monster card from among them to your hand, then send the
## rest to your discard pile.


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to search top 5 for a monster (or skip):",
		true)

	if selected.is_empty():
		return

	# Reveal top 5
	var revealed: Array[Dictionary] = []
	for _i in range(5):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	var monsters: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monsters.append(card)
		else:
			rest.append(card)

	if not monsters.is_empty():
		var chosen: Dictionary = await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, monsters, revealed,
			"Choose a monster card to add to your hand:")

		if not chosen.is_empty():
			var card_id: String = chosen.get("id", "")
			for i in range(monsters.size()):
				if monsters[i].get("id", "") == card_id:
					ctx.owner.hand.append(monsters[i])
					monsters.remove_at(i)
					break
			ctx.owner.hand_changed.emit()

	rest.append_array(monsters)
	ctx.owner.discard_pile.append_array(rest)
	if not rest.is_empty():
		ctx.owner.discard_changed.emit()
