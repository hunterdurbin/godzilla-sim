extends CardEffect
# Godzilla (2023)
# During your start phase, when rage would be set to 0, if rage >= 2,
# may discard 2 cards to set rage to 2 instead.
# Implemented via prevents_rage_reduction with a discard cost prompt.
# Note: The conditional discard-cost prevention needs a hook in TurnManager.execute_start_phase()
# to call an async method. For now, prevents_rage_reduction flags the condition but the cost
# prompt is not yet triggered. TODO: add async prevents_rage_reduction_with_cost support.


func get_bot_tags() -> Array[String]:
	return ["retains_rage"]


func prevents_rage_reduction(ctx: EffectContext) -> bool:
	# Only on own start phase when rage would be set to 0
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return false
	if ctx.owner.rage < 2:
		return false
	# Check if player has 2+ cards to discard
	return ctx.owner.hand.size() >= 2
