extends CardEffect
# Godzilla (Fest Godzilla II)
# If in zone >= opp monster zone → +5000 total counter power.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_total_cp_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 5000
	return 0
