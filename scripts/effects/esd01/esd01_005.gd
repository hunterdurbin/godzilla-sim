extends CardEffect

## ESD01-005: Godzilla(2023) - Monster Rank 2 (Burst I)
## <Burst1> You can play this card from rank I. If you do, send this card to your
## discard pile at the beginning of your next end phase.
## <Enter> Your opponent discards cards until they have 4 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 1


func on_enter(ctx: EffectContext) -> void:
	# Opponent discards to 4
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)
