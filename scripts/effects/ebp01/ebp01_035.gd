extends CardEffect

## EBP01-035: Godzilla(1989) - Monster Rank 3 (Blue)
## <Enter> Evolve all of your rank 4 or lower battle cards with <Evolution> in zones
## adjacent to this card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)

	for zi in adjacent:
		var zone_card := ctx.owner.get_zone_top_card(zi)
		if zone_card.is_empty():
			continue
		if zone_card.get("rank", 0) > 4:
			continue
		if not zone_card.has("evolution_rank"):
			continue
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zi)
