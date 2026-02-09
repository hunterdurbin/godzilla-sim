extends CardEffect
# Mechagodzilla(1974) (Battle R4)
# Counter phase start: if adjacent to monster, may discard all hand for +1000 CP per card.

var _bonus_cp: int = 0


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	_bonus_cp = 0
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Triggers on opponent's turn (when defending)

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	if monster_idx not in get_adjacent_zones(zone_idx):
		return

	if ctx.owner.hand.is_empty():
		return

	# Ask if they want to discard all hand
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card): return true,
		"Discard all hand for +1000 CP each? (select any card to confirm, skip to decline):",
		true
	)
	if selected.is_empty():
		return

	# The selected card is already discarded by select_hand_card. Discard the rest.
	var discarded_count := 1
	while not ctx.owner.hand.is_empty():
		ctx.owner.discard_pile.append(ctx.owner.hand.pop_back())
		discarded_count += 1
	ctx.owner.hand_changed.emit()
	ctx.owner.discard_changed.emit()
	_bonus_cp = discarded_count * 1000


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return 0
	return _bonus_cp
