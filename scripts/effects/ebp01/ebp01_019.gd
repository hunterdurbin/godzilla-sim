extends CardEffect

## EBP01-019: Kamacuras(1967) - Battle Rank 3
## <Awakening6> <Enter> If this card was played from your hand, search your deck for
## up to 2 <Kamacuras> battle cards, play them, then shuffle your deck.
## (Active if your monster card is in zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		return
	# Only from hand (not through evolution, search, or other effects)
	if ctx.card_data.get("played_from_effect", false):
		return

	# Rule 5.11.1.2: must avoid monster zone if possible
	var valid_zones: Array[int] = []
	var monster_idx := ctx.owner.monster_zone - 1
	for i in range(8):
		if i != monster_idx:
			valid_zones.append(i)

	for _i in range(2):
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

		var target_zone: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, valid_zones,
			"Choose a zone to play the searched card:")
		if target_zone < 0:
			break

		# Handle overload if zone occupied
		if ctx.owner.zone_has_cards(target_zone):
			var destroyed_stack: Array = ctx.owner.clear_zone(target_zone)
			EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
			ctx.owner.discard_changed.emit()

		selected["played_from_effect"] = true
		ctx.owner.push_zone_card(target_zone, selected)
		ctx.owner.zones_changed.emit()
		await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected)

		# Rule 5.11.1.3: must play to different zones if possible
		valid_zones.erase(target_zone)
