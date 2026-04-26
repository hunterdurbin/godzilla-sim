extends CardEffect

## EBP01-002: Godzilla(1954) - Monster Rank 2 (Burst I)
## <Burst1> <When Invading> Send the top card of your deck to your discard pile.
## If it is a monster card, <Destroy> 1 of your opponent's rank 5 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "mill_self"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func get_burst_rank() -> int:
	return 1


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var card := ctx.mill_one()
	if card.is_empty():
		return

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		tr("STR_EFF_DISCARDED_PILE"))

	if CardUtils.is_monster(card):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(c: Dictionary) -> bool: return ctx.field_rank(c, ctx.opponent.player_id) <= 5,
			tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 5)
