extends CardEffect

## EBP02-074: Bite Attack - Strategy Rank 7 (Green)
## Increase your monster card's <Rage> by 1 for each rank of your opponent's monster.


func on_enter(ctx: EffectContext) -> void:
	var opp_rank: int = ctx.opponent.get_monster_rank()
	if opp_rank > 0:
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += opp_rank
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
