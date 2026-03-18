extends CardEffect
# Moguera (Battle R6)
# <Enter> If played from hand and in zone 8, search deck for 1 Moguera battle card, play it.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "plays_other_cards", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7: # zone 8 = index 7
		return

	# Only from hand (not through evolution, search, or other effects)
	if ctx.card_data.get("played_from_effect", false):
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE \
			and CardEnums.CardTrait.MOGUERA in card.get("traits", []),
		"Search for a Moguera battle card to play:"
	)
	if found.is_empty():
		return

	var valid_zones := CardEffect.get_effect_play_zones(ctx.owner)

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		"Choose a zone to play the Moguera battle card:")
	if dest < 0:
		ctx.owner.main_deck.append(found)
		ctx.owner.main_deck.shuffle()
		ctx.owner.deck_changed.emit()
		return

	# Handle overload if zone occupied
	if ctx.owner.zone_has_cards(dest):
		var destroyed_stack: Array = ctx.owner.clear_zone(dest)
		EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
		ctx.owner.discard_changed.emit()

	ctx.owner.push_zone_card(dest, found)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, found, true)
