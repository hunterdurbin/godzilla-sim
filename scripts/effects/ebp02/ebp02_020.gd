extends CardEffect

## EBP02-020: Operation Yashiori -Conductorless train bombers- - Strategy Rank 6 (Red)
## <Enter> If you have 5 or more strategy cards in your discard pile, create
## "Conductorless Train Bombers" tokens in each of your unoccupied zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	# Count strategy cards in discard
	var strategy_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			strategy_count += 1

	if strategy_count < 5:
		return

	# Fill all empty zones with Train Bombers tokens
	var empty := ctx.owner.get_empty_zone_indices()
	for zone_idx in empty:
		await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T01", zone_idx)
