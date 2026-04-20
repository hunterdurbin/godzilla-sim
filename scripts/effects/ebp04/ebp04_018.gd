extends CardEffect
# Godzilla (Fest Godzilla II)
# <Enter> If 5+ monsters in discard → Destroy 1 opp Rank 6 or lower battle card.
# Continuous: if zone >= opp monster zone → +10000 threat.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= ctx.opponent.monster_zone:
		return 10000
	return 0


func on_enter(ctx: EffectContext) -> void:
	if _monster_discard_count(ctx) < 5:
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		"Destroy an opponent's Rank 6 or lower battle card:")


func _monster_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			count += 1
	return count
