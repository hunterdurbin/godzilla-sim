extends CardEffect
## EBP04-025: Godzilla Ultima - Monster Rank 4 (Green)
## <Enter> <Destroy> 1 of your opponent's strategy cards.
## <When Invading> If you have 10 or more green battle cards in your discard
## pile, your opponent discards until they have 3 cards in hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
		tr("STR_EFF_DESTROY_OPP_STRATEGY"))
	if chosen < 0:
		return

	var strat_card: Dictionary = ctx.opponent.strategy_zones[chosen]
	ctx.opponent.strategy_zones[chosen] = {}
	ctx.opponent.discard_pile.append(strat_card)
	ctx.opponent.strategy_zones_changed.emit()
	ctx.opponent.discard_changed.emit()


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if _green_battle_discard_count(ctx) < 10:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)


func _green_battle_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			count += 1
	return count
