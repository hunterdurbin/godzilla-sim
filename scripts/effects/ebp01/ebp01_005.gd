extends CardEffect

## EBP01-005: Godzilla(1955) - Monster Rank 4 (Burst III)
## <Burst3> <Enter> Your opponent discards cards until they have 4 cards remaining in their hand.


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)
