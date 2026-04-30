extends CardEffect
## EBP04-013: Godzilla (2000) - Monster Rank 3 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, reveal and
## discard the top 3 cards of your deck. Of the revealed cards' ranks, <Destroy>
## all of your opponent's battle cards in the same zone number and retreat your
## opponent's monster card in the same zone number backwards by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Both effects apply. When both are eligible, the player
##   picks the resolution order (destroy-then-retreat or retreat-then-destroy);
##   either is permitted per "and" effects. Retreat fires at most once even if
##   multiple revealed ranks match the opponent's monster zone.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "retreats_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count: int = 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
	return monster_count >= 5


func on_enter(ctx: EffectContext) -> void:
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
	if monster_count < 5:
		return

	var revealed := await ctx.mill(3)
	if revealed.is_empty():
		return

	# Collect unique ranks from revealed cards
	var ranks: Array[int] = []
	for card in revealed:
		var r: int = card.get("rank", 0)
		if r > 0 and r not in ranks:
			ranks.append(r)

	# Battle-card zones to destroy: opp zones (rank-1) holding a battle card.
	var destroy_zones: Array[int] = []
	for rank in ranks:
		var zone_idx: int = rank - 1
		if zone_idx < 0 or zone_idx > 7:
			continue
		if not ctx.opponent.get_zone_top_card(zone_idx).is_empty():
			destroy_zones.append(zone_idx)

	var can_retreat: bool = (
		ctx.opponent.monster_zone in ranks and ctx.opponent.monster_zone > 1
	)

	await _resolve_destroy_and_retreat(ctx, destroy_zones, can_retreat)


func _resolve_destroy_and_retreat(
	ctx: EffectContext, destroy_zones: Array[int], can_retreat: bool
) -> void:
	# Apply destroy + retreat in player-chosen order. When both apply, prompt
	# for the order; if only one applies, run it directly.
	var destroy_first: bool = true
	if not destroy_zones.is_empty() and can_retreat:
		var zone_list: String = ", ".join(destroy_zones.map(func(z): return str(z + 1)))
		var chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id,
			[
				tr("STR_EFF_DESTROY_THEN_RETREAT_FMT") % zone_list,
				tr("STR_EFF_RETREAT_THEN_DESTROY_FMT") % zone_list,
			],
			tr("STR_EFF_CHOOSE_ORDER"))
		destroy_first = chosen != 1

	if destroy_first:
		if not destroy_zones.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, destroy_zones)
		if can_retreat and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(
				ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
	else:
		if can_retreat and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(
				ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
		if not destroy_zones.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, destroy_zones)
