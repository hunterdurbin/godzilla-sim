extends CardEffect

## EFC01-005: Godzilla Appears in Godzilla Festival - Strategy Rank 6 (Red)
## <Your Turn> When you play a monster card, reveal the top 5 cards of your deck.
## Add all cards with <Fest> to your hand and discard the rest.
## At the beginning of your counter phase, discard your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_monster_played(ctx: EffectContext, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	# Only during your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	# Reveal top 5 cards
	var count: int = mini(5, ctx.owner.main_deck.size())
	if count == 0:
		return
	var revealed: Array[Dictionary] = []
	for i in range(count):
		revealed.append(ctx.owner.main_deck[i])

	# Show all revealed cards
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		tr("STR_EFF_REVEALED_CARDS"))

	# Separate Fest cards from the rest
	var fest_cards: Array[Dictionary] = []
	var discard_cards: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.has_trait(card, CardEnums.CardTrait.FEST):
			fest_cards.append(card)
		else:
			discard_cards.append(card)

	# Remove revealed cards from deck (reverse order to preserve indices)
	for i in range(count - 1, -1, -1):
		ctx.owner.main_deck.remove_at(i)
	ctx.owner.deck_changed.emit()

	# Add Fest cards to hand
	for card in fest_cards:
		ctx.owner.hand.append(card)
	if not fest_cards.is_empty():
		ctx.owner.hand_changed.emit()

	# Discard the rest
	for card in discard_cards:
		ctx.owner.discard_pile.append(card)
	if not discard_cards.is_empty():
		ctx.owner.discard_changed.emit()


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	# Discard entire hand
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
