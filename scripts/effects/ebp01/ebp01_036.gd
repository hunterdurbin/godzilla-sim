extends CardEffect

## EBP01-036: Godzilla(1992) - Monster Rank 4 (Blue)
## <Enter> Evolve all of your battle cards with <Evolution> in zones adjacent to this card.
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
		if not zone_card.has("evolution_rank"):
			continue
		eligible.append(zi)

	await ctx.effect_handler.evolve_zones_in_order(ctx.owner.player_id, eligible)
