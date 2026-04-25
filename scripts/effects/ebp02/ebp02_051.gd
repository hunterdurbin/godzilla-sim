extends CardEffect

## EBP02-051: Mecha-King Ghidorah - Monster Rank 4 (Green)
## If there are 5 or more cards under this card, this card gains +3000 threat level
## for each of your opponent's unoccupied zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func bot_can_fulfill_threat_level(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_monster_stack(5)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if not ctx.has_monster_stack(5):
		return 0

	var empty_count: int = ctx.opponent.get_empty_zone_indices().size()
	return empty_count * 3000
