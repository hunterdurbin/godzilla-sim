extends CardEffect

## EBP02-T04: Chibi Godzilla 2nd Form - Token Battle Rank 8 (White)
## At the beginning of your end phase, <Destroy> this card and play 1 battle card
## named "Chibi Godzilla" from your discard pile.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)


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

	# Find "Chibi Godzilla" (EBP02-077) in discard pile
	var chibi_idx: int = -1
	for i in range(ctx.owner.discard_pile.size()):
		if ctx.owner.discard_pile[i].get("id", "") == "EBP02-077":
			chibi_idx = i
			break

	# Destroy self (token gets banished via banish_or_discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	if chibi_idx < 0:
		return

	# Play Chibi Godzilla from discard to the zone this token was in
	var chibi: Dictionary = ctx.owner.discard_pile.pop_at(chibi_idx)
	ctx.owner.discard_changed.emit()
	ctx.owner.push_zone_card(zone_idx, chibi)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, chibi)
