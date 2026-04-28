extends CardEffect

## ESD01-006: Godzilla(2023) - Monster Rank 3 (Burst II)
## <Burst2> You can play this card from rank II. If you do, send this card to your
## discard pile at the beginning of your next end phase.
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


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	# Destroy 1 of opponent's rank 4 or lower battle cards
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
