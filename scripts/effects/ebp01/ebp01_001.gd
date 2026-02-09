extends CardEffect

## EBP01-001: Godzilla(1954) - Monster Rank 1
## At the beginning of your counter phase, send the top card of your deck to your discard pile.
## If it is a monster card, increase this card's <Rage> by 1.


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

	if card.get("card_type") == CardEnums.CardType.MONSTER:
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
