extends CardEffect
## EBP04-036: Kaiser Ghidorah - Monster Rank 4 (Red, Blue, Green)
## This card gains +5000 threat for each color of battle card in your discard
## pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size() * 5000
