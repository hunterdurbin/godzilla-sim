extends CardEffect
## EBP04-074: Rodan (1956) - Battle Rank 6 (White)
## <Enter> <Destroy> 1 of your opponent's strategy cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_any_strategy_in_play()


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
