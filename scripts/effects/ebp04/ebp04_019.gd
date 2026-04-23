extends CardEffect
## EBP04-019: Godzilla (Fest Godzilla II) - Monster Rank 4 (Blue)
## If this is in a zone equal to or greater than your opponent's monster card's
## and you have 5 or more monster cards in your discard pile, increase this
## card's threat by +10000 and add +10000 to your total counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "boosts_cp"]


func _condition_met(ctx: EffectContext) -> bool:
	if ctx.owner.monster_zone < ctx.opponent.monster_zone:
		return false
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			count += 1
	return count >= 5


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return 10000 if _condition_met(ctx) else 0


func get_total_cp_modifier(ctx: EffectContext) -> int:
	return 10000 if _condition_met(ctx) else 0
