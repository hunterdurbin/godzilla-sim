extends CardEffect

## ESD02-002: Godzilla(1989) - Monster Rank 2
## <Enter> <Destroy> 1 of your opponent's rank 4 or lower battle cards.
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


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool:
			return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
