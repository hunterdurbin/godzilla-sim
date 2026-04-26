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
	# Collect eligible zones: rank 4 or lower with Evolution
	var eligible: Array[int] = ctx.owner.get_zone_top_indices_matching(
		func(c: Dictionary) -> bool:
			return c.has("evolution_rank") \
				and ctx.field_rank(c, ctx.owner.player_id) <= 4)

	await ctx.effect_handler.evolve_zones_in_order(ctx.owner.player_id, eligible)
