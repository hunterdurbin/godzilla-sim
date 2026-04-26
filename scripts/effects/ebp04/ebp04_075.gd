extends CardEffect
## EBP04-075: Hyper Spiral Beam - Strategy Rank 1 (Red)
## <Opponent's Turn> At the beginning of their counter phase, discard the top
## card from your main deck. If that card is a Monster card, <Destroy> 1 of your
## opponent's battle cards in the same column as your monster card.
##
## Tested: No
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
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(top_card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

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
