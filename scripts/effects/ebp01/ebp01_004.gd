extends CardEffect

## EBP01-004: Godzilla(1954) - Monster Rank 4 (Burst III)
## <Burst3> When this card reaches zone 8, <Destroy> all battle cards in each player's zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 3


func on_monster_advance(ctx: EffectContext, _from_zone: int, to_zone: int) -> void:
	if to_zone != 8:
		return
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zones(ctx.owner, all_zones)
	await ctx.effect_handler.destroy_zones(ctx.opponent, all_zones)
