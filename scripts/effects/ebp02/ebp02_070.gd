extends CardEffect

## EBP02-070: Godzilla vs. SpaceGodzilla - Strategy Rank 3 (Green)
## <Opponent's Turn> Your opponent cannot play strategy cards.
## (Does not destroy cards already in play.)
## <Opponent's Turn> At the beginning of the main phase, your opponent may discard
## cards until they have 5 cards remaining in their hand. If they discard at least
## 1 card, <Destroy> this card.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func blocks_opponent_strategy_plays(ctx: EffectContext) -> bool:
	# Only active during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return false
	return true


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	# Only active during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	# Opponent (the turn player) may discard to 5 to destroy this card
	if ctx.opponent.hand.size() <= 5:
		return

	# Offer the opponent a choice: discard down to 5 cards to destroy this strategy
	# Use hand_card_selection to let opponent opt-in (allow_skip = true means they can decline)
	var discard_count: int = ctx.opponent.hand.size() - 5

	# Ask if opponent wants to discard (select any card as confirmation, skip to decline)
	var chosen: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.opponent.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Discard %d card(s) to destroy Godzilla vs. SpaceGodzilla? (Select a card to confirm, skip to decline)" % discard_count,
		true)

	if chosen.is_empty():
		return  # Opponent declined

	# Opponent chose to discard — the first card was already discarded by select_hand_card.
	# Discard remaining cards if needed.
	if discard_count > 1:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 5)

	# Destroy this strategy card
	_destroy_self(ctx)


func _destroy_self(ctx: EffectContext) -> void:
	for i in range(2):
		if ctx.owner.strategy_zones[i].get("id", "") == ctx.card_data.get("id", ""):
			var card: Dictionary = ctx.owner.strategy_zones[i]
			ctx.owner.strategy_zones[i] = {}
			ctx.owner.discard_pile.append(card)
			ctx.owner.strategy_zones_changed.emit()
			ctx.owner.discard_changed.emit()
			return
