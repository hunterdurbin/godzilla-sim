extends CardEffect
# Manda(2004) (Battle R3)
# If same column as opponent monster, +3000 CP.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx in get_opponent_column_zones(zone_idx):
		return 3000
	return 0
