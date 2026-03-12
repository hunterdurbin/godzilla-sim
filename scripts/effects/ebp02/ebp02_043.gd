extends CardEffect

## EBP02-043: Gigan(2004) - Monster Rank 3 (Green)
## Each of your battle cards in zones adjacent to this card gain +1000 counter power
## for each card under this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var cards_under: int = ctx.owner.monster_stack.size()
	if cards_under == 0:
		return {}

	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)
	var mods: Dictionary = {}
	var bonus: int = 1000 * cards_under

	for adj_zi in adjacent:
		if ctx.owner.zone_has_cards(adj_zi):
			mods[adj_zi] = bonus

	return mods
