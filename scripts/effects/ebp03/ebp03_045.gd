extends CardEffect
# Mothra(larva)(2003) (Battle R4)
# If adjacent to your monster card, +3000 CP.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var monster_idx: int = ctx.owner.monster_zone - 1
	if monster_idx in get_adjacent_zones(zone_idx):
		return 3000
	return 0
