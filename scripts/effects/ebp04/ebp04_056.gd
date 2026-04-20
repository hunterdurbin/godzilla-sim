extends CardEffect
# Kumonga (2004)
# If in same column as opp monster AND opp has 0 rage → opp cannot invade.


func get_bot_tags() -> Array[String]:
	return ["blocks_invade"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func prevents_opponent_invasion(ctx: EffectContext) -> bool:
	if ctx.opponent.rage != 0:
		return false
	return _is_in_opponent_monster_column(ctx)


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
