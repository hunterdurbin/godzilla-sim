extends CardEffect

## EBP01-076: Destroy All Monsters - Strategy Rank 2 (White)
## When your monster card invades this turn, <Destroy> 1 of your opponent's battle cards.
##
## NOTE: This is a persistent strategy effect that triggers on invasion during the turn
## it was played. Implemented via on_monster_advance during main phase.


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Only during invasion (main phase)
	if ctx.game_state.current_phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(_card: Dictionary) -> bool: return true,
		"Choose an opponent's battle card to destroy:")
