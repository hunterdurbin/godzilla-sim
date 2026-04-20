extends CardEffect
# Ganimes
# <Awakening 4> If in same column as opp's GREEN monster → +5000 CP.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone < 4:
		return 0
	if CardEnums.CardColor.GREEN not in ctx.opponent.current_monster.get("colors", []):
		return 0
	if _is_in_opponent_monster_column(ctx):
		return 5000
	return 0


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
