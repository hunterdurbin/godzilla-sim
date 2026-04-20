extends CardEffect
# Godzilla Aquatilius
# Own counter phase start: discard top of deck; if green battle → opp discards to 4.


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "mill_self"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(top_card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	var is_green_battle: bool = (
		top_card.get("card_type") == CardEnums.CardType.BATTLE and
		CardEnums.CardColor.GREEN in top_card.get("colors", [])
	)
	if is_green_battle:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)
