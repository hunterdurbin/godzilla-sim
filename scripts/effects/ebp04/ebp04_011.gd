extends CardEffect
## EBP04-011: Type 3 Kiryu (Modified) - Monster Rank 4 (Red, Blue)
## If you have 1 or more Blue and Red battle cards each in your zones, this
## gains +10,000 threat.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var has_blue: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.BLUE))
	var has_red: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.RED))
	if has_blue and has_red:
		return 10000
	return 0
