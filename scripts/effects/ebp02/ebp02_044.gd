extends CardEffect

## EBP02-044: Modified Gigan - Monster Rank 4 (Green)
## <When Invading> If your opponent's monster card is in zones 6-8, reduce their <Rage> by 2.
## At the beginning of your end phase, if your opponent's monster card is in zones 1-5,
## increase this card's <Rage> by 2.


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.opponent.monster_zone >= 6 and ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage = max(0, ctx.opponent.rage - 2)
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	if ctx.opponent.monster_zone <= 5:
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += 2
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
