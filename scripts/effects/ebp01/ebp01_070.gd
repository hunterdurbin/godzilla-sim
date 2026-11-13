extends CardEffect

## EBP01-070: Baragon(1968) - Battle Rank 5 (White)
## <Enter> Look at the top card of your deck. You may send it to your discard pile
## or place it back on top of your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.arrange_deck_top(
		ctx.owner.player_id, 1, tr("STR_EFF_DECK_LOOK_TOP"))
