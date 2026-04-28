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


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)

	# Collect eligible zones
	var eligible: Array[int] = []
	for zi in adjacent:
		var zone_card := ctx.owner.get_zone_top_card(zi)
		if zone_card.is_empty():
			continue
		if ctx.field_rank(zone_card, ctx.owner.player_id) > 4:
			continue
		if not zone_card.has("evolution_rank"):
			continue
		eligible.append(zi)

	await ctx.effect_handler.evolve_zones_in_order(ctx.owner.player_id, eligible)
