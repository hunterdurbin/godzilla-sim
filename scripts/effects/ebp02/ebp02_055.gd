extends CardEffect

## EBP02-055: SpaceGodzilla - Monster Rank 3 (Green)
## <Awakening4> If there are 3 or more "Crystals" in your zones, your opponent
## cannot play battle cards in zones in the same column as this card.
## (Does not destroy cards already there.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_blocked_opponent_zones(ctx: EffectContext) -> Array[int]:
	# Awakening4: only active when monster is at zone 4+
	if ctx.owner.monster_zone < 4:
		return []
	# Need 3+ Crystals tokens
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") < 3:
		return []
	# Block opponent zones in same column as this monster
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	return get_opponent_column_zones(monster_zone_idx)
