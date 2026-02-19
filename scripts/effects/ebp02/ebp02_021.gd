extends CardEffect

## EBP02-021: Godzilla(1993) - Monster Rank 3 (Blue)
## All of your rank 5 or lower battle cards in zones adjacent to this card
## gain +3000 counter power.
##
## Tested: Yes
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
		var adj_card := ctx.owner.get_zone_top_card(adj_zi)
		if not adj_card.is_empty() and ctx.field_rank(adj_card, ctx.owner.player_id) <= 5:
			mods[adj_zi] = 3000

	return mods
