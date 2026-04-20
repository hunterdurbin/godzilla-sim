extends CardEffect
# Multipurpose Fighting System-3 (Battle)
# Own counter phase start: may place an Invade 2 card from strategy zones under this.
# If there is a card under this → +10000 counter power.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	# Find invade2 strategy cards in strategy zones
	var valid_strat: Array[int] = []
	for i in range(ctx.owner.strategy_zones.size()):
		var sz_card: Dictionary = ctx.owner.strategy_zones[i]
		if not sz_card.is_empty() and sz_card.get("invasion_icon", 0) == 2:
			valid_strat.append(i)
	if valid_strat.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_strategy_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_strat,
		"Place an Invade 2 strategy card under this (or skip):")
	if chosen < 0:
		return

	var strat_card: Dictionary = ctx.owner.strategy_zones[chosen]
	ctx.owner.strategy_zones[chosen] = {}
	ctx.owner.strategy_changed.emit()

	# Place under this card
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		ctx.effect_handler.place_card_under_zone(ctx.owner, strat_card, my_zone)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0
	var cards_under: Array = ctx.owner.get_cards_under_top(my_zone)
	return 10000 if not cards_under.is_empty() else 0
