extends CardEffect
## EBP04-016: Godzilla(Fest GodzillaⅡ) - Monster Rank 1 (Blue)
## If the number of the zone this card is in is equal to or greater than the number of
## the zone the opponent’s monster card is in, this card gains +3000 threat level.
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
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 3000
	return 0
