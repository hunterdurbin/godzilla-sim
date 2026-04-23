extends CardEffect
## EBP04-057: King Caesar (2004) - Battle Rank 3 (Green)
## If there is a non-green battle card in your zones, this gains +3000 counter
## power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var has_non_green_battle: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and not CardUtils.has_color(c, CardEnums.CardColor.GREEN))
	return 3000 if has_non_green_battle else 0
