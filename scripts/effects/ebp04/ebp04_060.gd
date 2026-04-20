extends CardEffect
# Valkyrie
# If [Mechagodzilla City] (EBP04-086) is in play → +3000 CP.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for sz_card in ctx.owner.strategy_zones:
		if sz_card.get("name", "") == "Mechagodzilla City":
			return 3000
	return 0
