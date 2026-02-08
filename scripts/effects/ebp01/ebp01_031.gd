extends CardEffect

## EBP01-031: Space Beam - Strategy Rank 5
## If your monster card has 2 or more <Rage>, your opponent discards cards until they
## have 2 cards remaining in their hand.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
