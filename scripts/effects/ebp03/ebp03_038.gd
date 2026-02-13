extends CardEffect
# Multi-purpose Fighting System-3 (Battle R6)
# Counter start: if opponent has 2+ rage, Destroy all your battle cards adjacent to this.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return  # Own turn only
	if ctx.opponent.rage < 2:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var adjacent := get_adjacent_zones(zone_idx)
	var zones_to_destroy: Array[int] = []
	for adj_zi in adjacent:
		if not ctx.owner.is_zone_empty(adj_zi):
			zones_to_destroy.append(adj_zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.owner, zones_to_destroy)
