extends CardEffect
# Godzilla (Fest Godzilla II)
# If in zone >= opp monster zone → +3000 threat.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 3000
	return 0
