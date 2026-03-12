extends CardEffect

## EBP02-T04: Chibi Godzilla 2nd Form - Token Battle Rank 8 (White)
## At the beginning of your end phase, <Destroy> this card and play 1 battle card
## named "Chibi Godzilla" from your discard pile.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Destroy self (token gets banished via banish_or_discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	# Search discard for a battle card named "Chibi Godzilla"
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("name", "") == "Chibi Godzilla",
		"Play a Chibi Godzilla from your discard pile:")

	if selected.is_empty():
		return

	# Play selected Chibi Godzilla to the zone this token was in
	ctx.owner.push_zone_card(zone_idx, selected)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected)
