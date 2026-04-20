extends CardEffect
# Godzilla Telestorius
# For each opp battle card in same column as this → +10000 threat.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "column_dependent_monster_self"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)
	var count: int = 0
	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			count += 1
	return count * 10000
