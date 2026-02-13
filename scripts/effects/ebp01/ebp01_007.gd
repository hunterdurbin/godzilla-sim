extends CardEffect

## EBP01-007: Godzilla(1975) - Monster Rank 4 (Burst III)
## <Burst3> <When Invading> When this card <Destroy> your battle cards,
## reduce your opponent's <Rage> by 2.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 3


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Check if the zone the monster invaded into had a battle card (crushed during movement)
	# Zone state is captured at collection time since crush resolves before deferred abilities
	if ctx.metadata.get("zone_had_card", false):
		var reduction: int = mini(ctx.opponent.rage, 2)
		if reduction > 0:
			ctx.opponent.rage -= reduction
			ctx.opponent.rage_changed.emit(ctx.opponent.rage)
