extends CardEffect
# Godzilla(2002) R1
# At the beginning of your end phase, you may discard 1 battle card from hand. If you do, draw 1.


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE,
		"Discard a battle card to draw 1 (or skip):",
		true
	)
	if not selected.is_empty():
		ctx.owner.draw_cards(1)
