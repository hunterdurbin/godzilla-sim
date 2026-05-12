extends CardEffect
## EBP04-019: Godzilla(Fest GodzillaⅡ) - Monster Rank 4 (Blue)
## If the number of the zone this card occupies is greater than or equal to the number
## of the zone the opponent’s monster card occupies, and you have 5 or more monster
## cards in your discard pile, this card gains +10,000 threat level, and your total
## counter power is increased by +10,000.
##
## Tested: Yes
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


func get_counter_power_modifier(ctx: EffectContext) -> int:
	return 10000 if _condition_met(ctx) else 0
