extends CardEffect

## EBP01-001: Godzilla(1954) - Monster Rank 1
## At the beginning of your counter phase, send the top card of your deck to your discard pile.
## If it is a monster card, increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()
	ctx.effect_handler.log_message.emit(
		GameLog.effect_milled_card(ctx.owner.player_id, ctx.card_data.get("id", ""), card.get("id", ""))
	)

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		tr("STR_EFF_DISCARDED_PILE"))

	if CardUtils.is_monster(card):
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1)
		ctx.effect_handler.log_message.emit(
			GameLog.effect_gained_rage_from_mill(ctx.owner.player_id, ctx.card_data.get("id", ""), ctx.owner.rage, card.get("id", ""))
		)
