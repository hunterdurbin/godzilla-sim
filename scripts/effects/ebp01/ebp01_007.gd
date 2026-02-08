extends CardEffect

## EBP01-007: Godzilla(1975) - Monster Rank 4 (Burst III)
## <Burst3> <When Invading> When this card <Destroy> your battle cards,
## reduce your opponent's <Rage> by 2.


func get_burst_rank() -> int:
	return 3


func on_when_invading(ctx: EffectContext, _from_zone: int, to_zone: int) -> void:
	# Check if the zone the monster is invading into has a battle card (will be crushed)
	var zone_idx: int = to_zone - 1
	if zone_idx >= 0 and zone_idx < 8 and not ctx.owner.is_zone_empty(zone_idx):
		var reduction: int = mini(ctx.opponent.rage, 2)
		if reduction > 0:
			ctx.opponent.rage -= reduction
			ctx.opponent.rage_changed.emit(ctx.opponent.rage)
