extends CardEffect

## EBP01-041: Godzilla(2000) - Monster Rank 1 (Blue)
## <When Invading> <Destroy> 1 of your opponent's rank 4 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 4


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
