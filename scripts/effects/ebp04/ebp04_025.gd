extends CardEffect
# Godzilla Ultima
# <Enter> Destroy 1 opp strategy card.
# <When Invading> If 10+ green battle cards in discard → opp discards to 3.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "disrupts_hand"]


func on_enter(ctx: EffectContext) -> void:
	# Find opponent strategy zones with cards
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


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if _green_battle_discard_count(ctx) < 10:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)


func _green_battle_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			count += 1
	return count
