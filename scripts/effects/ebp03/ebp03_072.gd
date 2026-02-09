extends CardEffect
# Petit Railgun (Strategy R1)
# Destroy all opponent battle cards in same column as your monster.


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var opp_column_zones := get_opponent_column_zones(monster_idx)

	var zones_to_destroy: Array[int] = []
	for opp_zi in opp_column_zones:
		if not ctx.opponent.is_zone_empty(opp_zi):
			zones_to_destroy.append(opp_zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
