extends CardEffect

## EBP02-045: King Ghidorah(1964) - Monster Rank 2 (Green)
## This card gains +3000 threat level for each rank of your opponent's monster.
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
	return ctx.opponent.get_monster_rank() * 3000
