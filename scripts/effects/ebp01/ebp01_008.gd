extends CardEffect

## EBP01-008: Godzilla(2004) - Monster Rank 3 (Burst II)
## <Burst2> <Enter> Advance your opponent's monster card by 1 zone.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone < 8:
		ctx.opponent.monster_zone += 1
		ctx.opponent.monster_changed.emit()
