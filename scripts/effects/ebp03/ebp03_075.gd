extends CardEffect
# Yakusugi (Strategy R3)
# <Base>
# <Your Turn> Counter start: evolve 1 of your R4 or lower battle cards with Evolution.
#
# Tested: No, Looks good at glance
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	for i in range(8):
		var card := owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("rank", 0) <= 4 and card.get("evolution_rank", -1) >= 0:
			return true
	return false


func is_base_strategy() -> bool:
	return true


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return # Your turn only

	# Find zones with R4 or lower battle cards that have Evolution
	var valid_zones: Array[int] = []
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if card.is_empty():
			continue
		if ctx.field_rank(card, ctx.owner.player_id) > 4:
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
