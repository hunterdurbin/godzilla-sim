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
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty() or zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if CardEnums.CardColor.GREEN not in zone_card.get("colors", []):
			return 3000
	return 0
