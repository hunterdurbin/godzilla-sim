extends CardEffect
# Moguera (Battle R6)
# <Enter> If this card was played from your hand and is in zone 8, search your deck for
# up to 1 <《Moguera》> battle card, play it, then shuffle your deck.
#
# Tested: Yes
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
		func(card): return CardUtils.is_battle(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.MOGUERA),
		tr("STR_EFF_EBP03_036_SEARCH")
	)
	if found.is_empty():
		return

	var valid_zones := CardEffect.get_effect_play_zones(ctx.owner)

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP03_036_ZONE"))
	if dest < 0:
		ctx.owner.main_deck.append(found)
		ctx.owner.main_deck.shuffle()
		ctx.owner.deck_changed.emit()
		return

	await ctx.effect_handler.play_battle_card_from_deck(ctx.owner.player_id, found, dest)
