extends CardEffect

## EBP02-032: Biollante Rose Form - Battle Rank 4 (Blue)
## <Evolution7> <Biollante> At the beginning of your main phase, you may play a rank 7
## or lower <Biollante> battle card from your deck by placing it on top of this card.


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

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)
