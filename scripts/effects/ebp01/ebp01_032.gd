extends CardEffect

## EBP01-032: Heat Ray Charge - Strategy Rank 6
## Draw 2 cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(2)
