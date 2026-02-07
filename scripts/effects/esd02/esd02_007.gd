extends CardEffect

## ESD02-007: Mothra(larva)(1992) - Battle Rank 2
## <Evolution5> <Mothra> At the beginning of your main phase, you may search your deck
## for a rank 5 or lower <Mothra> battle card and play it by stacking it on top of this card.


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	# Only on owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := _find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
