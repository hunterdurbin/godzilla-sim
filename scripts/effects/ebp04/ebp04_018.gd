extends CardEffect
## EBP04-018: Godzilla(Fest GodzillaⅡ) - Monster Rank 3 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, <Destroy> 1 of your
## opponent’s rank 6 or lower battle cards.
## If the number of the zone this card occupies is greater than or equal to the number
## of the zone the opponent’s monster card occupies, this card gains +10,000 threat
## level.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)


func _monster_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			count += 1
	return count
