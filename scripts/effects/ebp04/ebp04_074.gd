extends CardEffect
# Rodan (1956)
# <Enter> Destroy 1 opp strategy card.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	for sz in opponent.strategy_zones:
		if not sz.is_empty():
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var valid_strat: Array[int] = []
	for i in range(ctx.opponent.strategy_zones.size()):
		if not ctx.opponent.strategy_zones[i].is_empty():
			valid_strat.append(i)
	if valid_strat.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_strategy_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_strat,
		"Destroy an opponent's strategy card:")
	if chosen < 0:
		return

	var strat_card: Dictionary = ctx.opponent.strategy_zones[chosen]
	ctx.opponent.strategy_zones[chosen] = {}
	ctx.opponent.discard_pile.append(strat_card)
	ctx.opponent.strategy_changed.emit()
	ctx.opponent.discard_changed.emit()
