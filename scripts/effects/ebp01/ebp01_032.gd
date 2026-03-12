extends CardEffect

## EBP01-032: Heat Ray Charge - Strategy Rank 6
## Draw 2 cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(2)
