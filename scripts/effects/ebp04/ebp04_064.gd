extends CardEffect
# Jet Jaguar (2021)
# Own counter phase start: if 10+ green in discard → may Destroy this to reduce opp rage by 3.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.opponent.rage < 3:
		return

	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			green_count += 1
	if green_count < 10:
		return

	var selected := await ctx.effect_handler.select_choice(
		ctx.owner.player_id,
		["Destroy this card to reduce opponent's Rage by 3", "Skip"],
		"Jet Jaguar (2021) — choose:")
	if selected != 0:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 3)
