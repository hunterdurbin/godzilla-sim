extends CardEffect

## EBP02-077: Chibi Godzilla - Battle Rank 6 (White)
## At the beginning of your main phase, send the top 2 cards of your deck
## to your discard pile. If a <Godzilla> card was sent to your discard pile
## this way, <Destroy> this card and play a "Chibi Godzilla 2nd Form" token.


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Mill top 2 cards
	var found_godzilla: bool = false
	for _i in range(2):
		if ctx.owner.main_deck.is_empty():
			break
		var milled: Dictionary = ctx.owner.main_deck.pop_front()
		ctx.owner.discard_pile.append(milled)
		var traits: Array = milled.get("traits", [])
		if CardEnums.CardTrait.GODZILLA in traits:
			found_godzilla = true

	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	if not found_godzilla:
		return

	# Destroy self (this card is a normal battle card, goes to discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	# Play Chibi Godzilla 2nd Form token in the zone this card was in
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T04", zone_idx)
