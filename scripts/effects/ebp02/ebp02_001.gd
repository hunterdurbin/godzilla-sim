extends CardEffect

## EBP02-001: Giant Unknown Creature - Monster Rank 1 (Red)
## <Opponent's Turn> At the beginning of the counter phase, you may discard 1 strategy
## card from your hand to increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return # Opponent's turn only

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP02_001_PROMPT"),
		true)

	if not selected.is_empty():
		ctx.effect_handler.log_message.emit(
			GameLog.effect_gained_rage(ctx.owner.player_id, ctx.card_data.get("id", ""), ctx.owner.rage + 1, 1))
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1)
