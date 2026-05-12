extends CardEffect
## EBP04-075: Hyper Spiral Beam - Strategy Rank 1 (Red)
## <Opponent’s Turn> At the beginning of the counter phase, send the top card of your
## deck to your discard pile. If it is a monster card, <Destroy> 1 of your opponent’s
## battle cards in the same column as your monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func is_base_strategy() -> bool:
	return false


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var top_card := await ctx.mill_one()
	if top_card.is_empty():
		return

	if not CardUtils.is_monster(top_card):
		return

	var valid_zones := ctx.get_opponent_column_zones_with_cards(ctx.owner.monster_zone - 1)
	if valid_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
		tr("STR_EFF_DESTROY_OPP_SAME_COLUMN"))
	if chosen >= 0:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
