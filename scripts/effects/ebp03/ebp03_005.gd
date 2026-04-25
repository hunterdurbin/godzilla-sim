extends CardEffect
# Godzilla(2001) R4
# <Burst3>
# <Awakening8> Your counter start: discard R5+ battle for +3 rage, then Destroy all opponent R7-.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 7


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if not owner.is_awakening(8):
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5):
			return true
	return false


func get_burst_rank() -> int:
	return 3


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_opponent_turn():
		return
	if not ctx.is_awakening(8):
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_005_PROMPT"),
		true
	)
	if not selected.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 3)

		var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 7)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
