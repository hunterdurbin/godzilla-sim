extends CardEffect
# Multi-purpose Fighting System-3 R4
# <Enter> Choose 1 opponent zone in same column, Destroy all opponent R6- in that zone + adjacent.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var opp_column_zones := get_opponent_column_zones(monster_idx)

	if opp_column_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, opp_column_zones,
		"Choose an opponent zone in the same column:")
	if chosen < 0:
		return

	# Collect the chosen zone + adjacent zones
	var target_zones: Array[int] = [chosen]
	for adj in get_adjacent_zones(chosen):
		if adj not in target_zones:
			target_zones.append(adj)

	# Destroy all R6- battle cards in those zones
	var zones_to_destroy: Array[int] = []
	for zi in target_zones:
		var card := ctx.opponent.get_zone_top_card(zi)
		if not card.is_empty() and card.get("rank", 0) <= 6:
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
