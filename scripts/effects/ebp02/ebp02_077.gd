extends CardEffect

## EBP02-077: Chibi Godzilla - Battle Rank 6 (White)
## At the beginning of your main phase, send the top 2 cards of your deck
## to your discard pile. If a <Godzilla> card was sent to your discard pile
## this way, <Destroy> this card and play a "Chibi Godzilla 2nd Form" token.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "plays_other_cards"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.MAIN, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Mill top 2 cards
	var milled_cards: Array[Dictionary] = ctx.owner.mill_cards(2)
	if not milled_cards.is_empty():
		ctx.effect_handler.log_message.emit(
			GameLog.effect_milled_cards(ctx.owner.player_id, ctx.card_data.get("id", ""), milled_cards)
		)
		await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, milled_cards, milled_cards,
			"Sent to discard pile:")
	var found_godzilla: bool = false
	for card in milled_cards:
		if CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
			found_godzilla = true
			break

	if not found_godzilla:
		return

	# Destroy self (this card is a normal battle card, goes to discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	# Play Chibi Godzilla 2nd Form token in the zone this card was in
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T04", zone_idx)
