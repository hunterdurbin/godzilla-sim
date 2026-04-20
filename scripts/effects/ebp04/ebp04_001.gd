extends CardEffect
# Godzilla (2004)
# <Opponent's Turn> Counter phase start: if no battle cards in same column → +1 Rage.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)

	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			return

	var old_rage := ctx.owner.rage
	ctx.owner.rage += 1
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
