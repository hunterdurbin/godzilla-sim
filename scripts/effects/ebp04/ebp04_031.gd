extends CardEffect
## EBP04-031: Monster X - Monster Rank 1 (Red, Blue, Green)
## This card's X Threat increases by +3000 for each color of battle card in
## your zones. In addition, if the opponent has 1 or less battle cards in
## their zones, they cannot counter this.
## <Resonance> Red, Blue, Green.
## - You may only use Battle Cards with <Final Wars>.
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
	return _count_zone_colors(ctx) * 3000


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
