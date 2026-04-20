extends CardEffect
# Mechagodzilla (2018)
# <Enter> If 4+ other green battle cards in own zones → discard 1 green card from deck.


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_enter(ctx: EffectContext) -> void:
	var my_zone: int = find_zone_of_card(ctx)
	var green_count: int = 0
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if (not zone_card.is_empty() and
				zone_card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in zone_card.get("colors", [])):
			green_count += 1

	if green_count < 4:
		return

	# Find a green card in deck to discard (optional)
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardEnums.CardColor.GREEN in card.get("colors", []),
		"Discard 1 green card from your deck (or skip):")
	if not found.is_empty():
		ctx.owner.discard_pile.append(found)
		ctx.owner.discard_changed.emit()
		ctx.owner.deck_changed.emit()
