extends CardEffect

## EBP01-076: Destroy All Monsters - Strategy Rank 2 (White)
## When your monster card invades this turn, <Destroy> 1 of your opponent's battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_invasion_observed": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(_card: Dictionary) -> bool: return true,
		tr("STR_EFF_DESTROY_OPP_BATTLE"))
