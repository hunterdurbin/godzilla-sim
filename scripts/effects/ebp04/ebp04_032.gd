extends CardEffect
## EBP04-032: Monster X - Monster Rank 2 (Red, Blue, Green)
## This card's threat level X is equal to 10,000 times the number of different
## colors among battle cards in your zones. If your opponent's zones have 1 or
## fewer battle cards, this card cannot be countered.
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
	return _count_zone_colors(ctx) * 10000


func get_counter_immunity_threshold(ctx: EffectContext) -> int:
	var opp_card_count: int = 0
	for i in range(8):
		if ctx.opponent.zone_has_cards(i):
			opp_card_count += 1
	if opp_card_count <= 1:
		return 999999
	return 0


func _count_zone_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in zone_card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
