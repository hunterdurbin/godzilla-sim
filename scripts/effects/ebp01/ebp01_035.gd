extends CardEffect

## EBP01-035: Godzilla(1989) - Monster Rank 3 (Blue)
## <Enter> Evolve all of your rank 4 or lower battle cards with <Evolution> in zones
## adjacent to this card.
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

	# Collect eligible zones
	var eligible: Array[int] = []
	for zi in adjacent:
		var zone_card := ctx.owner.get_zone_top_card(zi)
		if zone_card.is_empty():
			continue
		if zone_card.get("rank", 0) > 4:
			continue
		if not zone_card.has("evolution_rank"):
			continue
		eligible.append(zi)

	# Let the player choose the order when multiple zones are eligible
	while not eligible.is_empty():
		var zi: int
		if eligible.size() == 1:
			zi = eligible.pop_back()
		else:
			var options: Array[String] = []
			for ez in eligible:
				var card := ctx.owner.get_zone_top_card(ez)
				options.append("Zone %d: %s" % [ez + 1, card.get("name", "?")])
			var chosen: int = await ctx.effect_handler.select_choice(
				ctx.owner.player_id, options, "Choose which zone to evolve next:")
			zi = eligible.pop_at(chosen)
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zi)
