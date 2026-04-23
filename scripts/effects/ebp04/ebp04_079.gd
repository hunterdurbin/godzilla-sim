extends CardEffect
## EBP04-079: Godzilla Final Wars - Strategy Rank 7 (Red)
## Reveal the top 7 cards of your deck, play all <Final Wars> battle cards among
## them and discard the rest.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards", "searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	var revealed: Array[Dictionary] = []
	for i in range(7):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())

	if revealed.is_empty():
		return

	ctx.effect_handler.cards_revealed_requested.emit(
		ctx.owner.player_id, revealed, "Revealed from deck top:")
	await ctx.effect_handler._cards_revealed_resolved

	var final_wars_cards: Array[Dictionary] = []
	var other_cards: Array[Dictionary] = []
	for card in revealed:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardTrait.FINAL_WARS in card.get("traits", [])):
			final_wars_cards.append(card)
		else:
			other_cards.append(card)

	for card in other_cards:
		ctx.owner.discard_pile.append(card)

	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	# Play each Final Wars battle card into an available zone
	for card in final_wars_cards:
		var empty_zones := ctx.owner.get_empty_zone_indices()
		if empty_zones.is_empty():
			ctx.owner.discard_pile.append(card)
			ctx.owner.discard_changed.emit()
			continue

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, empty_zones,
			"Play %s — choose a zone:" % card.get("name", "card"))
		if chosen < 0:
			ctx.owner.discard_pile.append(card)
			ctx.owner.discard_changed.emit()
			continue

		await ctx.effect_handler.play_battle_card_from_deck(ctx.owner.player_id, card, chosen)
