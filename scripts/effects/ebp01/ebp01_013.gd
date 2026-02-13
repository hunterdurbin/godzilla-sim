extends CardEffect

## EBP01-013: Godzilla(Fest Godzilla) - Monster Rank 3 (Burst II)
## <Burst2> <Enter> If you have 4 or more battle cards in your zones,
## reduce your opponent's <Rage> by 1.
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
	var battle_count: int = 0
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			battle_count += 1
	if battle_count >= 4 and ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
