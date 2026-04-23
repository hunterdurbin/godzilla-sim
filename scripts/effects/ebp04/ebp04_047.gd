extends CardEffect
## EBP04-047: Monster X - Battle Rank 5 (Blue)
## This card's counter power X is equal to 3000 times the number of different
## colors among battle cards in your zones (white included).
## <Evolution 8> <Kaiser Ghidorah>
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "evolution"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.MAIN, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	var battle_tops: Array[Dictionary] = ctx.owner.get_zone_top_cards_matching(
		func(c: Dictionary) -> bool: return CardUtils.is_battle(c))
	for zone_card in battle_tops:
		for c: int in zone_card.get("colors", []):
			if c not in colors:
				colors.append(c)
	return colors.size() * 3000
