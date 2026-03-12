extends CardEffect

## EBP01-065: Godzilla vs. Destoroyah - Strategy Rank 6 (Blue)
## <Destroy> all of your opponent's battle cards in zones 1-5.
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
	var zones_to_destroy: Array[int] = []
	for i in range(5): # zones 1-5 = indices 0-4
		if ctx.opponent.zone_has_cards(i):
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
