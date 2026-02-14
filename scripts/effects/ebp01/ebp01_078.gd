extends CardEffect

## EBP01-078: Godzilla Attacks - Strategy Rank 4 (White)
## Advance your monster card to zone 6.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		ctx.owner.monster_zone = 6
		ctx.owner.monster_changed.emit()
