extends CardEffect
# Minilla (2004)
# If you have a rank 1 strategy card in play → +3000 counter power.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("rank", 99) == 1:
			return 3000
	return 0
