extends CardEffect
# Servum
# <Awakening 4> If in area adjacent to monster → +3000 CP.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone < 4:
		return 0
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0
	var monster_idx: int = ctx.owner.monster_zone - 1
	if my_zone in get_adjacent_zones(monster_idx):
		return 3000
	return 0
