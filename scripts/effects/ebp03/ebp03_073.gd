extends CardEffect
# All-Weapon Attack (Strategy R4)
# Reveal the top 3 cards of your deck and send them to your discard pile; <Destroy> all
# of your opponent’s battle cards in zones whose numbers match the ranks of the
# revealed cards, if your opponent's monster card occupies 1 of those zones, your
# opponent’s monster card retreats backward by 1 zone.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "destroys_zone", "retreats_opponent"]


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.mill(3)
	if revealed.is_empty():
		return

	var matching_ranks: Array[int] = []
	for card in revealed:
		var rank: int = card.get("rank", 0)
		if rank >= 1 and rank <= 8 and rank not in matching_ranks:
			matching_ranks.append(rank)

	# Destroy opponent battle cards in zones matching revealed ranks
	# rank N = zone N = index N-1
	var zones_to_destroy: Array[int] = []
	for rank in matching_ranks:
		var zone_idx: int = rank - 1
		if ctx.opponent.zone_has_cards(zone_idx):
			zones_to_destroy.append(zone_idx)

	var can_retreat: bool = (
		ctx.opponent.monster_zone in matching_ranks and ctx.opponent.monster_zone > 1
	)

	# Apply destroy + retreat in player-chosen order. When both apply, prompt
	# for the order; if only one applies, run it directly.
	var destroy_first: bool = true
	if not zones_to_destroy.is_empty() and can_retreat:
		var zone_list: String = ", ".join(zones_to_destroy.map(func(z): return str(z + 1)))
		var chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id,
			[
				tr("STR_EFF_DESTROY_THEN_RETREAT_FMT") % zone_list,
				tr("STR_EFF_RETREAT_THEN_DESTROY_FMT") % zone_list,
			],
			tr("STR_EFF_CHOOSE_ORDER"))
		destroy_first = chosen != 1

	if destroy_first:
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
		if can_retreat and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(
				ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
	else:
		if can_retreat and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(
				ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
