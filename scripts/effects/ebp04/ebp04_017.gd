extends CardEffect
## EBP04-017: Godzilla (Fest Godzilla II) - Monster Rank 2 (Blue)
## If this card is in a zone greater than or equal to your opponent's monster
## card, add +5000 to your total counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_total_cp_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 5000
	return 0
