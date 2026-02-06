extends CardEffect

## ESD01-015: Operation Wadatsumi - Strategy Rank 7
## Your opponent discards cards until they have 2 cards remaining in their hand.
##
## NOTE: This is a strategy card with an immediate effect when played (on_enter).


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
