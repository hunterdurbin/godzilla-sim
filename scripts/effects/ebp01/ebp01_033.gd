extends CardEffect

## EBP01-033: Final Showdown - Strategy Rank 8
## You can play this card from your hand with its rank reduced by 1 for each zone
## your monster card invaded this turn.
## <Destroy> all battle cards of both players.
##
## NOTE: The rank reduction mechanic requires rules engine support.
## The destruction effect is implemented here.


func on_enter(ctx: EffectContext) -> void:
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zones(ctx.owner, all_zones)
	await ctx.effect_handler.destroy_zones(ctx.opponent, all_zones)
