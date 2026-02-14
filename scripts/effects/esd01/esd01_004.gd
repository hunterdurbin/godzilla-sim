extends CardEffect

## ESD01-004: Godzilla(2023) - Monster Rank 4
## <When Invading> If this card has 2 or more <Rage>, your opponent discards
## cards until they have 2 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.rage >= 2:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
