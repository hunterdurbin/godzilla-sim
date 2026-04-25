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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP04_009_PROMPT"),
		true)
	if selected.is_empty():
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)
	var targetable: Array[int] = []
	for zi in col_zones:
		var opp_card := ctx.opponent.get_zone_top_card(zi)
		if not opp_card.is_empty() and ctx.field_rank(opp_card, ctx.opponent.player_id) <= 6:
			targetable.append(zi)
	if targetable.is_empty():
		return

	await ctx.effect_handler.destroy_zones(ctx.opponent, targetable)
