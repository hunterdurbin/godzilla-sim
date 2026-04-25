extends CardEffect
# Multi-purpose Fighting System-3 R3
# <Enter> If blue battle card in your zones, Destroy 1 opponent R5-.
# <Opponent's Turn> Counter start: if red battle in your zones, Destroy 1 opponent R5- in same column.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.BLUE))


func on_enter(ctx: EffectContext) -> void:
	if not _has_color_battle_in_zones(ctx, CardEnums.CardColor.BLUE):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card): return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 5)


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return # Opponent's turn only
	if not _has_color_battle_in_zones(ctx, CardEnums.CardColor.RED):
		return

	# Get opponent zones in same column as this monster
	var monster_idx: int = ctx.owner.monster_zone - 1
	var opp_column_zones := get_opponent_column_zones(monster_idx)

	var valid_zones: Array[int] = []
	for opp_zi in opp_column_zones:
		var opp_card := ctx.opponent.get_zone_top_card(opp_zi)
		if not opp_card.is_empty() and ctx.field_rank(opp_card, ctx.opponent.player_id) <= 5:
			valid_zones.append(opp_zi)

	if valid_zones.is_empty():
		return

	await ctx.effect_handler.destroy_chosen_zone(
		ctx.owner.player_id, ctx.opponent, valid_zones,
		tr("STR_EFF_EBP03_008_PROMPT"))


func _has_color_battle_in_zones(ctx: EffectContext, color: CardEnums.CardColor) -> bool:
	return ctx.owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.is_battle(c) and CardUtils.has_color(c, color))
