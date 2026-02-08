extends CardEffect

## EBP01-019: Kamacuras(1967) - Battle Rank 3
## <Awakening6> <Enter> If this card was played from your hand, search your deck for
## up to 2 <Kamacuras> battle cards, play them, then shuffle your deck.
## (Active if your monster card is in zone 6 or beyond.)


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		return
	# Only from hand (not through evolution or other effects)
	if ctx.card_data.get("played_through_evolution", false):
		return

	for _i in range(2):
		var empty_zones := ctx.owner.get_empty_zone_indices()
		if empty_zones.is_empty():
			break

		var selected := await ctx.effect_handler.search_deck(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				if card.get("card_type") != CardEnums.CardType.BATTLE:
					return false
				var traits: Array = card.get("traits", [])
				return CardEnums.CardTrait.KAMACURAS in traits,
			"Search for a Kamacuras battle card to play:"
		)
		if selected.is_empty():
			break

		empty_zones = ctx.owner.get_empty_zone_indices()
		if empty_zones.is_empty():
			break

		var target_zone: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, empty_zones,
			"Choose a zone to play the searched card:")
		if target_zone < 0:
			break

		ctx.owner.push_zone_card(target_zone, selected)
		ctx.owner.zones_changed.emit()
		await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected)
