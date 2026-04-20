extends CardEffect
# Type 3 Kiryu (Modified)
# If you have 1 or more Blue AND Red battle cards each in your zones → +10000 threat.


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
