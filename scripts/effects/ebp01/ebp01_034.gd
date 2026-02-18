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

	# Rule 5.11.1.2: adjacent zones, avoiding monster zone if possible
	var valid_adjacent: Array[int] = []
	for zi in adjacent:
		if zi != monster_zone_idx:
			valid_adjacent.append(zi)
	if valid_adjacent.is_empty():
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

	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_adjacent,
		"Choose an adjacent zone to play the card:")
	if target_zone < 0:
		return

	# Handle overload if zone occupied
	if ctx.owner.zone_has_cards(target_zone):
		var destroyed_stack: Array = ctx.owner.clear_zone(target_zone)
		EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
		ctx.owner.discard_changed.emit()

	ctx.owner.push_zone_card(target_zone, selected)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected)
