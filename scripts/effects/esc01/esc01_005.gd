extends CardEffect

## ESC01-005: King Ghidorah(1991) - Monster Rank 3 (Green)
## <When Invading> If there are 3 or more cards under this card, reveal the top
## card of your deck and send it to your discard pile; <Destroy> 1 of your
## opponent's battle cards with rank equal to or lower than the revealed card's
## rank.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Destroy filter compares the target's field rank against
## the revealed card's printed rank.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "mill_self"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_monster_stack(3)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# monster_stack holds the cards under the current monster
	if not ctx.owner.has_monster_stack(3):
		return

	var revealed := await ctx.mill_one()
	if revealed.is_empty():
		return

	var max_rank: int = revealed.get("rank", 0)
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(c: Dictionary) -> bool: return ctx.field_rank(c, ctx.opponent.player_id) <= max_rank,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % max_rank)
