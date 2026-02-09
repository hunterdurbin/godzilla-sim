extends CardEffect
# Manda(2004) (Battle R3)
# If same column as opponent monster, +3000 CP.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx in get_opponent_column_zones(zone_idx):
		return 3000
	return 0
