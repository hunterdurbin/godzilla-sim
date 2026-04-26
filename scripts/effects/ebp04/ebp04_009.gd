extends CardEffect
## EBP04-009: Godzilla (2016) 3rd Form - Monster Rank 3 (Red)
## <Opponent's Turn> At the beginning of their counter phase, you may discard 1
## strategy card from your hand to <Destroy> all of your opponent's Rank 6 or
## lower battle cards in the same column as this.
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


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP04_009_PROMPT"),
		true)
	if selected.is_empty():
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var targetable: Array[int] = []
	for zi in ctx.get_opponent_column_zones_with_cards(monster_idx):
		var opp_card := ctx.opponent.get_zone_top_card(zi)
		if ctx.field_rank(opp_card, ctx.opponent.player_id) <= 6:
			targetable.append(zi)
	if targetable.is_empty():
		return

	await ctx.effect_handler.destroy_zones(ctx.opponent, targetable)
