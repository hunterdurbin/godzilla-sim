extends CardEffect
# Gigan (2004)
# Cannot advance nor invade.
# <Your Turn> Main phase start: may discard invade2 card → this card is countered.
# <Opponent's Turn> Main phase start: opp may discard invade2 → this card is countered.


func get_bot_tags() -> Array[String]:
	return []


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.MAIN}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return

	var is_own_turn := ctx.game_state.current_player_id == ctx.owner.player_id
	var acting_player: PlayerState = ctx.owner if is_own_turn else ctx.opponent
	var acting_player_id: int = acting_player.player_id

	var selected := await ctx.effect_handler.select_hand_card(
		acting_player_id,
		func(card: Dictionary) -> bool: return card.get("invasion_icon", 0) == 2,
		"Discard an Invade 2 card to counter this Gigan (or skip):",
		true)
	if selected.is_empty():
		return

	# Force counter this card
	if ctx.effect_handler.action_handler:
		await ctx.effect_handler.force_counter(ctx.owner.player_id)
