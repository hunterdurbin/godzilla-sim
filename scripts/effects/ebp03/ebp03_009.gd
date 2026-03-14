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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var opp_column_zones := get_opponent_column_zones(monster_idx)

	if opp_column_zones.is_empty():
		return

	await ctx.effect_handler.destroy_zone_and_adjacent(
		ctx.owner.player_id, ctx.opponent, opp_column_zones,
		"Choose an opponent zone in the same column:", 6)
