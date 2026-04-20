extends CardEffect
# Spacegodzilla
# <When Invading> Play 3 [Crystal] tokens.
# <Awakening 6> If 3+ Crystal tokens in zones → +10000 counter power.


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards", "boosts_cp"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.create_tokens_in_zones(ctx.owner, "EBP02-T03", 3)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone < 6:
		return 0
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") >= 3:
		return 10000
	return 0
