extends CardEffect
## EBP04-003: Godzilla (2004) - Monster Rank 3 (Red)
## <Burst 2> (You can play this card from rank II. If you do, send this card to your
## discard pile at the beginning of that turn’s end phase.)
## <Enter> If you have a rank 1 strategy card in play, <Destroy> 1 of your opponent’s
## rank 6 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_burst_rank() -> int:
	return 2


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_battle_card_zone_indices().is_empty()


func on_enter(ctx: EffectContext) -> void:
	if not _has_rank1_strategy(ctx):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)


func _has_rank1_strategy(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("rank", 99) == 1:
			return true
	return false
