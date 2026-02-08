extends CardEffect

## EBP01-057: Mothra(imago)(1992) - Battle Rank 7 (Blue)
## <Enter> Choose 2 battle cards in your zones, you may swap their positions.
## Your rank 5 or lower battle cards in zones adjacent to this card gain +3000 counter power.


func on_enter(ctx: EffectContext) -> void:
	# Find all occupied zones (for swapping)
	var occupied: Array[int] = []
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			occupied.append(i)

	if occupied.size() >= 2:
		# Choose first card to swap
		var first: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, occupied,
			"Choose the first battle card to swap:", true)
		if first >= 0:
			var second_choices: Array[int] = []
			for zi in occupied:
				if zi != first:
					second_choices.append(zi)
			if not second_choices.is_empty():
				var second: int = await ctx.effect_handler.select_zone_target(
					ctx.owner.player_id, ctx.owner.player_id, second_choices,
					"Choose the second battle card to swap with:", true)
				if second >= 0:
					# Swap the entire stacks
					var stack_a: Array = ctx.owner.zones[first]
					ctx.owner.zones[first] = ctx.owner.zones[second]
					ctx.owner.zones[second] = stack_a
					ctx.owner.zones_changed.emit()


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var zone_idx := _find_zone_of_card(ctx)
	if zone_idx < 0:
		return {}

	var adjacent := get_adjacent_zones(zone_idx)
	var mods: Dictionary = {}

	for adj_zi in adjacent:
		var adj_card := ctx.owner.get_zone_top_card(adj_zi)
		if not adj_card.is_empty() and adj_card.get("rank", 0) <= 5:
			mods[adj_zi] = 3000

	return mods


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
