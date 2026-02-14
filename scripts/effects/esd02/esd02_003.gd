extends CardEffect

## ESD02-003: Godzilla(1992) - Monster Rank 3
## <Enter> Play up to 2 rank 4 or lower battle cards with <Evolution> from your discard pile
## in zones adjacent to this card.
## (For example, if this card is in zone 7, the adjacent zones are 4, 6, and 8.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var player := ctx.owner
	var monster_zone_idx: int = player.monster_zone - 1

	# Get adjacent zones that are empty
	var adjacent := get_adjacent_zones(monster_zone_idx)
	var empty_adjacent: Array[int] = []
	for z in adjacent:
		if player.is_zone_empty(z):
			empty_adjacent.append(z)

	if empty_adjacent.is_empty():
		return

	# Play up to 2 matching cards from discard pile
	for _i in range(2):
		if empty_adjacent.is_empty():
			break

		# Search discard for rank 4 or lower battle cards with Evolution
		var selected := await ctx.effect_handler.search_discard(
			player.player_id,
			func(card: Dictionary) -> bool:
				if card.get("card_type") != CardEnums.CardType.BATTLE:
					return false
				if card.get("rank", 0) > 4:
					return false
				return card.has("evolution_rank"),
			"Search discard pile for a rank 4 or lower battle card with Evolution to play:"
		)
		if selected.is_empty():
			break

		# Let player choose which adjacent zone to place it in
		var target_zone: int = await ctx.effect_handler.select_zone_target(
			player.player_id, player.player_id, empty_adjacent,
			"Choose an adjacent zone to play the card in:")
		if target_zone < 0:
			break

		player.push_zone_card(target_zone, selected)
		player.zones_changed.emit()
		await ctx.effect_handler.trigger_enter(player.player_id, selected)

		# Remove the chosen zone from available targets
		empty_adjacent.erase(target_zone)
