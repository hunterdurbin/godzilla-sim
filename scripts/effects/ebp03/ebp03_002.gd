extends CardEffect
# Godzilla(2001) R2
# <Opponent's Turn> <Awakening4> Counter start: discard R5+ battle for +1 rage.
# <Awakening8> Your counter start: discard R5+ battle for +2 rage.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return

	var is_own_turn := ctx.game_state.current_player_id == ctx.owner.player_id

	# Effect 1: Opponent's turn, Awakening4, +1 rage
	if not is_own_turn and ctx.owner.monster_zone >= 4:
		await _try_discard_for_rage(ctx, 1)
	# Effect 2: Your turn, Awakening8, +2 rage
	elif is_own_turn and ctx.owner.monster_zone >= 8:
		await _try_discard_for_rage(ctx, 2)


func _try_discard_for_rage(ctx: EffectContext, rage_gain: int) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE and card.get("rank", 0) >= 5,
		"Discard a rank 5+ battle card to gain %d rage (or skip):" % rage_gain,
		true
	)
	if not selected.is_empty():
		var old_rage := ctx.owner.rage
		ctx.owner.rage += rage_gain
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
