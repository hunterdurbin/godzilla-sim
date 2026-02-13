extends CardEffect

## ESD02-010: Mothra(imago)(1992) - Battle Rank 5
## <Enter> If this card was played through evolution, draw 1 card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.card_data.get("played_through_evolution", false):
		ctx.owner.draw_cards(1)
