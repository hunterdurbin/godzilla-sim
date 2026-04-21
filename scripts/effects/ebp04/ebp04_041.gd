extends CardEffect
# New Gotengo
# Own counter phase start: if this is in area 8 → trigger all Enter abilities of monster.
# <Awakening 6> +3000 counter power.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7:  # Must be zone 8 (index 7)
		return

	await ctx.effect_handler.trigger_all_monster_enter_abilities(ctx.owner.player_id)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
