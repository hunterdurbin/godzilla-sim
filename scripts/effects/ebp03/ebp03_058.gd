extends CardEffect
# Zilla (Battle R4)
# End phase start: move to an adjacent horizontal zone.
# Then if adjacent to your monster, Destroy this card.


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# "Adjacent horizontal" = same row neighbors
	# Back row: zones 1-5 (indices 0-4), front row: zones 6-8 (indices 5-7)
	var horizontal_adj: Array[int] = []
	if zone_idx <= 4:
		# Back row
		if zone_idx > 0:
			horizontal_adj.append(zone_idx - 1)
		if zone_idx < 4:
			horizontal_adj.append(zone_idx + 1)
	else:
		# Front row
		if zone_idx > 5:
			horizontal_adj.append(zone_idx - 1)
		if zone_idx < 7:
			horizontal_adj.append(zone_idx + 1)

	# Filter to empty zones
	var valid: Array[int] = []
	for adj in horizontal_adj:
		if ctx.owner.is_zone_empty(adj):
			valid.append(adj)

	if valid.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid,
		"Move Zilla to an adjacent horizontal zone:")
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[zone_idx]
	ctx.owner.zones[zone_idx] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()

	# Check if now adjacent to own monster
	var monster_idx: int = ctx.owner.monster_zone - 1
	if monster_idx in get_adjacent_zones(dest):
		var destroyed_stack: Array = ctx.owner.clear_zone(dest)
		EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
		ctx.owner.zones_changed.emit()
		ctx.owner.discard_changed.emit()
		await ctx.effect_handler.trigger_revenge(ctx.owner.player_id, ctx.card_data)
