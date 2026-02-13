extends CardEffect
# Godzilla's Bite - Strategy R1 (Red)
# <Destroy> all of your opponent's battle cards in the same column as your
# monster card.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return
	var opponent_zones: Array[int] = get_opponent_column_zones(monster_zone_idx)
	var zones_to_destroy: Array[int] = []
	for zone_idx in opponent_zones:
		if not ctx.opponent.is_zone_empty(zone_idx):
			zones_to_destroy.append(zone_idx)
	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
