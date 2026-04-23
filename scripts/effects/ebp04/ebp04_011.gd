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
	var has_blue := false
	var has_red := false
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty() or zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		var colors: Array = zone_card.get("colors", [])
		if CardEnums.CardColor.BLUE in colors:
			has_blue = true
		if CardEnums.CardColor.RED in colors:
			has_red = true
	if has_blue and has_red:
		return 10000
	return 0
