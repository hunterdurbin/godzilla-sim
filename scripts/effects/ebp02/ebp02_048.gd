extends CardEffect

## EBP02-048: King Ghidorah(1991) - Monster Rank 2 (Green)
## <Enter> Send the top 3 cards of your deck to your discard pile.
## <When Invading> <Destroy> 3 of your opponent's rank 4 or lower battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.mill_cards(3)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	for _i in range(3):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
			"Choose an opponent's rank 4 or lower battle card to destroy:")
