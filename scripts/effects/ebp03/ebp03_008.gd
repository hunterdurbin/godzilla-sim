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


func on_enter(ctx: EffectContext) -> void:
	if not _has_color_battle_in_zones(ctx, CardEnums.CardColor.BLUE):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card): return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
		"Destroy 1 opponent rank 5 or lower battle card:")


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Opponent's turn only
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
		"Destroy 1 opponent rank 5 or lower battle card in same column:")


func _has_color_battle_in_zones(ctx: EffectContext, color: CardEnums.CardColor) -> bool:
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("card_type") == CardEnums.CardType.BATTLE:
			if color in card.get("colors", []):
				return true
	return false
