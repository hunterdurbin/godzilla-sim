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


func get_burst_rank() -> int:
	return 3


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.owner.monster_zone < 8:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE and card.get("rank", 0) >= 5,
		"Discard a rank 5+ battle card to gain 3 rage and Destroy opponent R7- (or skip):",
		true
	)
	if not selected.is_empty():
		var old_rage := ctx.owner.rage
		ctx.owner.rage += 3
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)

		var zones_to_destroy: Array[int] = []
		for i in range(8):
			var opp_card := ctx.opponent.get_zone_top_card(i)
			if not opp_card.is_empty() and opp_card.get("rank", 0) <= 7:
				zones_to_destroy.append(i)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
