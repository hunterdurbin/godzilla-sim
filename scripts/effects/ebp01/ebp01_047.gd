extends CardEffect

## EBP01-047: Orga - Battle Rank 3 (Blue)
## <Enter> Draw 1 card, then discard 1 card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(1)

	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Choose a card to discard:"
	)
	# select_hand_card already moves the card to discard
