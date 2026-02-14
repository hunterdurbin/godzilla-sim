extends CardEffect

## EBP01-034: Godzilla(1989) - Monster Rank 2 (Blue)
## <Enter> Select 1 rank 4 or lower battle card with <Evolution> from your discard pile
## and play it in a zone adjacent to this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)

	# Filter for empty adjacent zones
	var empty_adjacent: Array[int] = []
	for zi in adjacent:
		if ctx.owner.is_zone_empty(zi):
			empty_adjacent.append(zi)
	if empty_adjacent.is_empty():
		return

	# Search discard for rank 4 or lower battle card with Evolution
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			if card.get("rank", 0) > 4:
				return false
			return card.has("evolution_rank"),
		"Choose a rank 4 or lower battle card with Evolution from your discard pile:"
	)
	if selected.is_empty():
		return

	# Re-check empty adjacent zones
	empty_adjacent = []
	for zi in adjacent:
		if ctx.owner.is_zone_empty(zi):
			empty_adjacent.append(zi)
	if empty_adjacent.is_empty():
		return

	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty_adjacent,
		"Choose an adjacent zone to play the card:")
	if target_zone < 0:
		return

	ctx.owner.push_zone_card(target_zone, selected)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected)
