extends CardEffect
## EBP04-026: Spacegodzilla - Monster Rank 4 (Green)
## <When Invading> Play 3 “Crystals” tokens. (Tokens are prepared separately from your
## deck.)
## <Awakening 6> If there are 3 or more “Crystals” in your zones, increase your total
## counter power by +10,000. (Active if this card is in zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards", "boosts_cp"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.create_tokens_in_zones(ctx.owner, "EBP02-T03", 3)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if not ctx.is_awakening(6):
		return 0
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") >= 3:
		return 10000
	return 0
