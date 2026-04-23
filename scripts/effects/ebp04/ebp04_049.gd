extends CardEffect
## EBP04-049: Ebirah (2004) - Battle Rank 5 (Blue)
## At the beginning of your counter phase, if you have a Rank 8 or higher
## battle card in play, reveal and discard 1 card from the top of your deck.
## If it is a non-blue card decrease your opponent's <Rage> by -2. If it's a
## blue card <Destroy> 1 of your rank 8 or higher battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "mill_self"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var has_rank8_plus: bool = not ctx.effect_handler.get_zones_in_rank_range(
		ctx.owner.player_id, 8, -1).is_empty()
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

	var is_blue: bool = CardUtils.has_color(top_card, CardEnums.CardColor.BLUE)

	if not is_blue:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 2)
	else:
		var valid_zones: Array[int] = ctx.effect_handler.get_zones_in_rank_range(
			ctx.owner.player_id, 8, -1)
		if not valid_zones.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.owner.player_id, valid_zones,
				"Destroy 1 of your rank 8 or higher battle cards:")
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.owner, [chosen])
