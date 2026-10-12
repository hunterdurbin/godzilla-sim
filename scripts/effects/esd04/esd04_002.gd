extends CardEffect

## ESD04-002: Destoroyah Aggregate Form - Monster Rank 2 (Blue)
## <When Invading> Evolve 1 of your rank 6 or lower battle cards with
## <Evolution>. (If this card invades 2 zones, this activates twice.)
##
## Tested: Yes
## Known issues: None
## Edge cases: Mandatory — no skip when a valid card exists; silent when none.
## Rules: None
## Interactions: None
## Implementation notes: on_when_invading fires once per zone advanced, so an
##   invade-2 discard evolves twice naturally (the second pass sees the
##   freshly evolved top card). Rank cap uses field_rank (as EBP03-075).


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.rank_at_most(c, 6) and c.get("evolution_rank", -1) >= 0)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var valid_zones: Array[int] = ctx.owner.get_zone_top_indices_matching(func(c: Dictionary) -> bool:
		return ctx.field_rank(c, ctx.owner.player_id) <= 6 and c.get("evolution_rank", -1) >= 0)
	if valid_zones.is_empty():
		return

	var chosen := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_ESD04_002_PROMPT"))
	if chosen < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, chosen)
