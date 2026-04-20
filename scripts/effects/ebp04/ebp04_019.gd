extends CardEffect
# Godzilla (Fest Godzilla II)
# If zone >= opp monster zone AND 5+ monsters in discard → +10000 threat + +10000 total CP.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "boosts_cp"]


func _condition_met(ctx: EffectContext) -> bool:
	if ctx.owner.monster_zone < ctx.opponent.monster_zone:
		return false
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			count += 1
	return count >= 5


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return 10000 if _condition_met(ctx) else 0


func get_total_cp_modifier(ctx: EffectContext) -> int:
	return 10000 if _condition_met(ctx) else 0
