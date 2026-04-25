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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func is_base_strategy() -> bool:
	return false


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	if ctx.owner.main_deck.is_empty():
		return

	var top_card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(top_card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	if not CardUtils.is_monster(top_card):
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)

	var valid_zones: Array[int] = []
	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			valid_zones.append(zi)
	if valid_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
		tr("STR_EFF_DESTROY_OPP_SAME_COLUMN"))
	if chosen >= 0:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
