extends CardEffect
## EBP04-079: Godzilla Final Wars - Strategy Rank 7 (Red)
## Reveal the top 7 cards of your deck, play all <Final Wars> battle cards among
## them and discard the rest.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards", "searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 7)
	if revealed.is_empty():
		return

	var final_wars_cards: Array[Dictionary] = []
	var other_cards: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.has_trait(card, CardEnums.CardTrait.FINAL_WARS):
			final_wars_cards.append(card)
		else:
			other_cards.append(card)

	ctx.effect_handler.discard_cards(ctx.owner.player_id, other_cards)

	# Player picks the order to play each Final Wars card. The pick is
	# mandatory (rule says "play all"); zone selection per card is also
	# mandatory unless no empty zone is available, in which case the card
	# is discarded as a fallback.
	while not final_wars_cards.is_empty():
		var card: Dictionary = await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, final_wars_cards, final_wars_cards,
			tr("STR_EFF_EBP04_079_PICK"), false)
		if card.is_empty():
			# No-UI fallback or empty options — discard the rest defensively.
			ctx.effect_handler.discard_cards(ctx.owner.player_id, final_wars_cards)
			return
		final_wars_cards.erase(card)

		var empty_zones := ctx.owner.get_empty_zone_indices()
		if empty_zones.is_empty():
			ctx.effect_handler.discard_cards(ctx.owner.player_id, [card])
			continue

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, empty_zones,
			tr("STR_EFF_PLAY_NAMED_FMT") % card.get("name", "card"))
		if chosen < 0:
			ctx.effect_handler.discard_cards(ctx.owner.player_id, [card])
			continue

		await ctx.effect_handler.play_battle_card_from_deck(ctx.owner.player_id, card, chosen)
