extends CardEffect
# Yakusugi (Strategy R3)
# <Base>
# <Your Turn> Counter start: evolve 1 of your R4 or lower battle cards with Evolution.


func is_base_strategy() -> bool:
	return true


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return  # Your turn only

	# Find zones with R4 or lower battle cards that have Evolution
	var valid_zones: Array[int] = []
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if card.is_empty():
			continue
		if card.get("rank", 0) > 4:
			continue
		if card.get("evolution_rank", -1) < 0:
			continue
		valid_zones.append(i)

	if valid_zones.is_empty():
		return

	var chosen := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		"Choose a rank 4 or lower battle card with Evolution to evolve (or skip):", true)
	if chosen < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, chosen)
