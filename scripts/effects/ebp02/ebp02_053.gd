extends CardEffect

## EBP02-053: SpaceGodzilla - Monster Rank 2 (Green)
## <When Invading> Play 1 "Crystals" token.
## If there is a "Crystals" in your zones, this card gains +5000 threat level.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.create_tokens_in_empty_zones(ctx.owner, "EBP02-T03", 1)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") > 0:
		return 5000
	return 0
