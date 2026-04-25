extends CardEffect

## EBP01-057: Mothra(imago)(1992) - Battle Rank 7 (Blue)
## <Enter> Choose 2 battle cards in your zones, you may swap their positions.
## Your rank 5 or lower battle cards in zones adjacent to this card gain +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func on_enter(ctx: EffectContext) -> void:
	# Find all occupied zones (for swapping)
	var occupied: Array[int] = ctx.owner.get_occupied_zone_indices()

	if occupied.size() >= 2:
		# Choose first card to swap
		var first: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, occupied,
			tr("STR_EFF_SWAP_FIRST"), true)
		if first >= 0:
			var second_choices: Array[int] = []
			for zi in occupied:
				if zi != first:
					second_choices.append(zi)
			if not second_choices.is_empty():
				var second: int = await ctx.effect_handler.select_zone_target(
					ctx.owner.player_id, ctx.owner.player_id, second_choices,
					tr("STR_EFF_SWAP_SECOND"), true)
				if second >= 0:
					await ctx.effect_handler.swap_zones(ctx.owner, first, second)


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return {}

	var adjacent := get_adjacent_zones(zone_idx)
	var mods: Dictionary = {}

	for adj_zi in adjacent:
		var adj_card := ctx.owner.get_zone_top_card(adj_zi)
		if not adj_card.is_empty() and ctx.field_rank(adj_card, ctx.owner.player_id) <= 5:
			mods[adj_zi] = 3000

	return mods
