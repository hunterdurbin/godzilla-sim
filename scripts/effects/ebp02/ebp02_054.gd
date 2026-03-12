extends CardEffect

## EBP02-054: SpaceGodzilla - Monster Rank 3 (Green)
## <Enter> Play 2 "Crystals" tokens.
## Whenever this card's <Rage> is increased, <Destroy> 1 of your opponent's
## rank 5 or lower battle cards for each "Crystals" in your zones.
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
	await ctx.effect_handler.create_tokens_in_empty_zones(ctx.owner, "EBP02-T03", 2)


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# Only trigger when rage increases
	if new_rage <= old_rage:
		return

	var crystal_count: int = ctx.owner.count_zone_tokens_by_id("EBP02-T03")
	if crystal_count <= 0:
		return

	# Destroy up to crystal_count of opponent's rank 5 or lower battle cards
	for _i in range(crystal_count):
		var destroyed: Dictionary = await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool:
				return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
			"Destroy an opponent's rank 5 or lower battle card:")
		if destroyed.is_empty():
			break
