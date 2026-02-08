extends CardEffect

## EBP02-009: Godzilla(2023) - Monster Rank 4 (Red)
## <Burst3>
## When this card is discarded by the effect of Burst, return this card from your
## discard pile to your hand. [TODO: Needs burst discard hook - not yet implemented]
## <When Invading> Your opponent discards cards until they have 3 cards remaining.


func get_burst_rank() -> int:
	return 3


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
