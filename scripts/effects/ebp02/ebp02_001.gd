extends CardEffect

## EBP02-001: Giant Unknown Creature - Monster Rank 1 (Red)
## <Opponent's Turn> At the beginning of the counter phase, you may discard 1 strategy
## card from your hand to increase this card's <Rage> by 1.


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Opponent's turn only

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to gain 1 rage (or skip):",
		true)

	if not selected.is_empty():
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
