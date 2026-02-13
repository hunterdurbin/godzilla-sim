extends CardEffect

## EBP01-055: Battra(imago) - Battle Rank 6 (Blue)
## <Enter> Draw 1 card, then discard 1 card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(1)

	await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Choose a card to discard:"
	)
