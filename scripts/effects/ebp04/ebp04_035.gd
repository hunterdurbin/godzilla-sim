extends CardEffect
## EBP04-035: Kaizer Ghidorah - Monster Rank 4 (Red, Blue, Green)
## <Enter> Starting with the battle card in your opponent’s zone with the lowest number,
## <Destroy> battle cards one by one up to the number of different colors among battle
## cards in your discard pile.
##
## Tested: Yes
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

	# Pre-select target zones (lowest-numbered occupied zones, up to color_count).
	# Per Q523: target areas are chosen up front, then destroyed in order;
	# zones that can't be destroyed are skipped without re-targeting.
	var occupied: Array[int] = ctx.opponent.get_battle_card_zone_indices()
	var targets: Array[int] = occupied.slice(0, color_count)
	for zone_idx in targets:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [zone_idx])


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
