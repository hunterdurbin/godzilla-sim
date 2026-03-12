extends CardEffect

## EBP01-063: Guardians Awaken - Strategy Rank 4 (Blue)
## Evolve all of your rank 4 or lower battle cards with <Evolution>.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func on_enter(ctx: EffectContext) -> void:
	# Collect eligible zones
	var eligible: Array[int] = []
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if ctx.field_rank(zone_card, ctx.owner.player_id) > 4:
			continue
		if not zone_card.has("evolution_rank"):
			continue
		eligible.append(i)

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
