extends CardEffect

## ESD01-014: Godzilla Emerges - Strategy Rank 6
## If your monster card has 2 or more <Rage>, search your deck for up to 1 battle card
## named Godzilla(2023), play it, then shuffle your deck.
##
## NOTE: This is a strategy card with an immediate effect when played (on_enter).


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage < 2:
		return

	var player := ctx.owner
	var empty_zones := player.get_empty_zone_indices()
	if empty_zones.is_empty():
		return

	var selected := await ctx.effect_handler.search_deck(
		player.player_id,
		func(card: Dictionary) -> bool:
			return card.get("name", "") == "Godzilla(2023)" \
				and card.get("card_type") == CardEnums.CardType.BATTLE,
		"Search for a Godzilla(2023) battle card to play"
	)
	if not selected.is_empty():
		# Play it to the first empty zone
		var target_zone: int = empty_zones[0]
		player.push_zone_card(target_zone, selected)
		player.zones_changed.emit()
		# Trigger enter on the newly played card
		await ctx.effect_handler.trigger_enter(player.player_id, selected)
