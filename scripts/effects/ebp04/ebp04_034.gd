extends CardEffect
## EBP04-034: Kaiser Ghidorah - Monster Rank 3 (Red, Blue, Green)
## You can play this on top of a <Monster X> monster card in your zones.
## <Enter> If you have 3 or more colors of battle cards in your discard pile,
## <Destroy> 1 of your opponent's Rank 5 or lower battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func can_play_as_monster(ctx: EffectContext) -> bool:
	if ctx.card_data.get("played_from_effect", false):
		return false
	return CardUtils.has_trait(ctx.owner.current_monster, CardEnums.CardTrait.MONSTER_X)


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_all_zone_cards().is_empty()


func on_enter(ctx: EffectContext) -> void:
	if _count_discard_colors(ctx) < 3:
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 5)


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
