extends CardEffect
## EBP04-061: Mechagodzilla (2018) - Battle Rank 5 (Green)
## <Enter> If you have 4 or more other green battle cards in your zones, you may
## discard 1 green card from your deck and then shuffle your deck.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_enter(ctx: EffectContext) -> void:
	var my_zone: int = find_zone_of_card(ctx)
	var green_tops: Array[int] = ctx.owner.get_zone_top_indices_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.GREEN))
	var green_count: int = green_tops.size()
	if my_zone in green_tops:
		green_count -= 1

	if green_count < 4:
		return

	# Find a green card in deck to discard (optional)
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.has_color(card, CardEnums.CardColor.GREEN),
		"Discard 1 green card from your deck (or skip):")
	if not found.is_empty():
		ctx.owner.discard_pile.append(found)
		ctx.owner.discard_changed.emit()
		ctx.owner.deck_changed.emit()
