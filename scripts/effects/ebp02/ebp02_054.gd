extends CardEffect

## EBP02-054: SpaceGodzilla - Monster Rank 3 (Green)
## <Enter> Play 2 “Crystals” tokens. (Tokens are prepared separately from your deck.)
## Whenever this card's <Rage> is increased, <Destroy> 1 of your opponent's rank 5 or
## lower battle cards for each “Crystals” in your zones.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_rage_changed": {"direction": "increase"},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.create_tokens_in_zones(ctx.owner, "EBP02-T03", 2)


func on_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	var crystal_count: int = ctx.owner.count_zone_tokens_by_id("EBP02-T03")
	if crystal_count <= 0:
		return

	# Destroy 1 per Crystal (exact-N, clamped to available rank-5-or-lower targets)
	await ctx.effect_handler.destroy_zone_targets(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool:
			return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
		crystal_count, tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 5)
