extends CardEffect
## EBP04-016: Godzilla (Fest Godzilla II) - Monster Rank 1 (Blue)
## If this is in a zone greater than or equal to your opponent's monster card's,
## this gains +3000 threat.
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
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 3000
	return 0
