extends CardEffect

## EBP02-047: King Ghidorah(1991) - Monster Rank 1 (Green)
## Whenever this card advances, send the top card of your deck to your discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()
