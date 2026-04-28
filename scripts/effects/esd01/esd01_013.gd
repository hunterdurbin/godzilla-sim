extends CardEffect

## ESD01-013: Ginza Annihilated - Strategy Rank 4
## <Your Turn> Whenever your monster card's <Rage> is increased,
## <Destroy> 1 of your opponent's rank 6 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_rage_changed": {"own_turn": true, "direction": "increase"},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func on_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	# Destroy 1 of opponent's rank 6 or lower battle cards
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)
