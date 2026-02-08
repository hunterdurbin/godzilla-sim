extends CardEffect

## EBP01-032: Heat Ray Charge - Strategy Rank 6
## Draw 2 cards.


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(2)
