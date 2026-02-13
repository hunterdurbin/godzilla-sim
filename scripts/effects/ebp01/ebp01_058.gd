extends CardEffect

## EBP01-058: Biollante Plant Beast Form - Battle Rank 7 (Blue)
## If you have a <Biollante> card with <Evolution> in your discard pile, you can play
## this from your hand with its rank reduced by 2. (After being played, this card is rank 7.)
## <Enter> Return all cards in your discard pile to your deck then shuffle.
##
## NOTE: The rank reduction mechanic requires rules engine support.
## The enter effect is fully implemented.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.discard_pile.is_empty():
		return

	ctx.owner.main_deck.append_array(ctx.owner.discard_pile)
	ctx.owner.discard_pile.clear()
	ctx.owner.main_deck.shuffle()
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()
