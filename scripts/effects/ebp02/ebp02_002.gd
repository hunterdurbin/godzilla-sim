extends CardEffect

## EBP02-002: Godzilla(2016) 2nd Form - Monster Rank 2 (Red)
## If you have 1 or more strategy cards in play, this card gains +5000 threat level.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			return 5000
	return 0
