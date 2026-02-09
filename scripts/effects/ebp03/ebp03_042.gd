extends CardEffect

## EBP03-042: Ghogo - Battle Rank 2 (Blue)
## When your monster card invades, if this is in zone 8, you may put this card under one
## of your Mothra battle cards with Evolution. If you do, evolve that Mothra battle card.


func on_invasion_observed(ctx: EffectContext, invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	# Only when owner's monster invades
	if invading_player_id != ctx.owner.player_id:
		return

	# Must be in zone 8 (index 7)
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7:
		return

	# Find Mothra battle cards with Evolution in owner's zones
	var valid_zones: Array[int] = []
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("evolution_rank", -1) < 0:
			continue
		if CardEnums.CardTrait.MOTHRA not in zone_card.get("traits", []):
			continue
		valid_zones.append(i)

	if valid_zones.is_empty():
		return

	# Choose a Mothra card to place self under (optional)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		"Place Ghogo under a Mothra card with Evolution to evolve it (or skip):", true)

	if chosen < 0:
		return

	# Remove self from zone 8 and place under the chosen card
	var self_stack: Array = ctx.owner.clear_zone(my_zone)
	if not self_stack.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, self_stack[0], chosen)
		# Banish/discard any cards that were stacked under self
		if self_stack.size() > 1:
			EffectHandler.banish_or_discard(ctx.owner, self_stack.slice(1))
	ctx.owner.zones_changed.emit()

	# Evolve the chosen card
	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, chosen)
