extends CardEffect
# Mechagodzilla(1975) (Battle R7)
# Counter start: may move this card to an unoccupied zone.
# If same column as opponent monster, +3000 CP.


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Opponent's turn (defending)

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty,
		"Move this card to an empty zone (or skip):", true)
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[zone_idx]
	ctx.owner.zones[zone_idx] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _is_in_opponent_monster_column(ctx):
		return 3000
	return 0


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
