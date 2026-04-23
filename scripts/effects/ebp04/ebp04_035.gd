extends CardEffect
## EBP04-035: Kaiser Ghidorah - Monster Rank 4 (Red, Blue, Green)
## <Enter> <Destroy> one card at a time, in order, from your opponents lowest
## numbered area with a battle card up to the number of cards equal to the
## number of colors of battle cards in your discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var color_count: int = _count_discard_colors(ctx)
	if color_count == 0:
		return

	for _i in range(color_count):
		# Find lowest-numbered zone with a battle card
		var occupied: Array[int] = ctx.opponent.get_occupied_zone_indices()
		if occupied.is_empty():
			break
		await ctx.effect_handler.destroy_zones(ctx.opponent, [occupied[0]])


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
