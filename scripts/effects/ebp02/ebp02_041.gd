extends CardEffect

## EBP02-041: Gigan(1972) - Monster Rank 1 (Green)
## Each of your battle cards in zones adjacent to this card gain +1000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)
	var mods: Dictionary = {}

	for adj_zi in adjacent:
		if ctx.owner.zone_has_cards(adj_zi):
			mods[adj_zi] = 1000

	return mods
