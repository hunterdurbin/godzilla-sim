extends CardEffect
## EBP04-017: Godzilla (Fest Godzilla II) - Monster Rank 2 (Blue)
## If the number of the zone this card is in is equal to or greater than the number of
## the zone the opponent’s monster card is in, increase your total counter power by
## +5000.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 5000
	return 0
