extends CardEffect

## EBP02-T01: Conductorless Train Bombers - Token Battle Rank 2 (Red)
## <Enter> Reduce your opponent's <Rage> by 1.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		if ctx.effect_handler:
			await ctx.effect_handler.trigger_rage_changed(
				ctx.opponent.player_id, old_rage, ctx.opponent.rage)
