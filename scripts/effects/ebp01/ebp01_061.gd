extends CardEffect

## EBP01-061: Scale Attack - Strategy Rank 1 (Blue)
## If your opponent has 5 or more <Rage>, reduce their <Rage> by 3.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage >= 5:
		var reduction: int = mini(ctx.opponent.rage, 3)
		ctx.opponent.rage -= reduction
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
