extends CardEffect
# Destoroyah Perfect Form
# +5000 CP per own strategy card in play.
# -5000 CP per opp strategy card in play.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var own_strat: int = 0
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty():
			own_strat += 1

	var opp_strat: int = 0
	for sz_card in ctx.opponent.strategy_zones:
		if not sz_card.is_empty():
			opp_strat += 1

	return own_strat * 5000 - opp_strat * 5000
