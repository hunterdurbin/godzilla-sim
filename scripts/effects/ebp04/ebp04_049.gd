extends CardEffect
# Ebirah (2004)
# Own counter phase start: if rank 8+ battle card in play →
# reveal and discard top card of deck.
# If non-blue → opp rage -2. If blue → Destroy 1 own rank 8+ battle card.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "mill_self"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var has_rank8_plus := false
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.owner.player_id) >= 8:
			has_rank8_plus = true
			break
	if not has_rank8_plus:
		return

	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(top_card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	ctx.effect_handler.cards_revealed_requested.emit(
		ctx.owner.player_id, [top_card], "Revealed from deck top:")
	await ctx.effect_handler._cards_revealed_resolved

	var is_blue: bool = CardEnums.CardColor.BLUE in top_card.get("colors", [])

	if not is_blue:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 2)
	else:
		var valid_zones: Array[int] = []
		for i in range(8):
			var zone_card := ctx.owner.get_zone_top_card(i)
			if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.owner.player_id) >= 8:
				valid_zones.append(i)
		if not valid_zones.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.owner.player_id, valid_zones,
				"Destroy 1 of your rank 8 or higher battle cards:")
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.owner, [chosen])
