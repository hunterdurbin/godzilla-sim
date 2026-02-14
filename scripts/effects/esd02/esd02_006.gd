extends CardEffect

## ESD02-006: Godzilla(1995) - Monster Rank 4
## For each strategy card your opponent has in play, this card gains +5000 threat level.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var count := 0
	for sz_card in ctx.opponent.strategy_zones:
		if not sz_card.is_empty():
			count += 1
	return count * 5000
