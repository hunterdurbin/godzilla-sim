extends CardEffect
## EBP04-041: New Gotengo - Battle Rank 5 (Red)
## At the beginning of your counter phase, if this card is in area 8 trigger
## all <Enter> abilities of your monster card.
## <Awakening 6> This card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_opponent_turn():
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7:  # Must be zone 8 (index 7)
		return

	await ctx.effect_handler.trigger_all_monster_enter_abilities(ctx.owner.player_id)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(6):
		return 3000
	return 0
