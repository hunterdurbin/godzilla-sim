extends CardEffect
# Mechagodzilla(1974) (Battle R4)
# Counter phase start: if adjacent to monster, may discard all hand for +1000 CP per card.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None

var _bonus_cp: int = 0


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	_bonus_cp = 0
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return  # Own turn only

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
	var discarded_count: int = 1 + ctx.owner.hand.size()
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
	_bonus_cp = discarded_count * 1000


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	return _bonus_cp
