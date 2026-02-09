extends CardEffect
# Moguera (Battle R6)
# <Enter> If played from hand and in zone 8, search deck for 1 Moguera battle card, play it.


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7:  # zone 8 = index 7
		return

	# Check if played from hand (not through evolution or other means)
	if ctx.card_data.get("played_through_evolution", false):
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE \
			and CardEnums.CardTrait.MOGUERA in card.get("traits", []),
		"Search for a Moguera battle card to play:"
	)
	if found.is_empty():
		return

	# Let player choose an empty zone to play it in
	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		# No empty zones, must overwrite — let them pick any zone
		var all_zones: Array[int] = []
		for i in range(8):
			if i != zone_idx:
				all_zones.append(i)
		var dest := await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, all_zones,
			"Choose a zone to play the Moguera battle card:")
		if dest < 0:
			# Put card back in deck
			ctx.owner.main_deck.append(found)
			ctx.owner.main_deck.shuffle()
			ctx.owner.deck_changed.emit()
			return
		ctx.owner.push_zone_card(dest, found)
	else:
		var dest := await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, empty,
			"Choose a zone to play the Moguera battle card:")
		if dest < 0:
			ctx.owner.main_deck.append(found)
			ctx.owner.main_deck.shuffle()
			ctx.owner.deck_changed.emit()
			return
		ctx.owner.push_zone_card(dest, found)

	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, found)
