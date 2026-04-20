extends CardEffect
# Inherited Life
# <Base> Do not move to discard at start phase.
# <Your Turn> When you decrease your Monster's Rage, put those cards underneath this.
# 15th card: destroy all opp battle cards.
# 22nd card: opp discards entire hand.
# 30th card: you win the game.


func get_bot_tags() -> Array[String]:
	return ["win_condition"]


func is_base_strategy() -> bool:
	return true


func _get_cards_under_count(ctx: EffectContext) -> int:
	var strategy_idx := _find_own_strategy_zone(ctx)
	if strategy_idx < 0:
		return 0
	return ctx.effect_handler.get_cards_under_top(ctx.owner, strategy_idx).size()


func _find_own_strategy_zone(ctx: EffectContext) -> int:
	for i in range(ctx.owner.strategy_zones.size()):
		var top := ctx.owner.strategy_zones[i]
		if not top.is_empty() and top[0].get("id", "") == ctx.card_data.get("id", ""):
			return i
	return -1


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# Only trigger on own turn when rage decreases
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	var delta := old_rage - new_rage
	if delta <= 0:
		return

	var strategy_idx := _find_own_strategy_zone(ctx)
	if strategy_idx < 0:
		return

	var count_before := ctx.effect_handler.get_cards_under_top(ctx.owner, strategy_idx).size()

	# The rage cards that were discarded are already gone; we track count via delta
	# We place placeholder markers representing each rage reduction card
	# In practice, place the actual discarded cards under — but rage discard
	# happens in game logic before this trigger fires. We track count via instance var.
	# TODO: Wire rage discard cards to be placed under this card via ActionHandler.
	# For now, increment a stored count by delta and check milestones.
	var count_after := count_before + delta

	# Check milestones crossed
	for milestone in [15, 22, 30]:
		if count_before < milestone and count_after >= milestone:
			await _trigger_milestone(ctx, milestone)


func _trigger_milestone(ctx: EffectContext, milestone: int) -> void:
	match milestone:
		15:
			ctx.effect_handler.log_message.emit(
				"Inherited Life: 15 rage cards — destroying all opponent battle cards!")
			var zones_to_destroy: Array[int] = []
			for i in range(8):
				if not ctx.opponent.get_zone_top_card(i).is_empty():
					zones_to_destroy.append(i)
			if not zones_to_destroy.is_empty():
				await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
		22:
			ctx.effect_handler.log_message.emit(
				"Inherited Life: 22 rage cards — opponent discards entire hand!")
			while not ctx.opponent.hand.is_empty():
				var card := ctx.opponent.hand.pop_back() as Dictionary
				ctx.opponent.discard_pile.append(card)
			ctx.opponent.hand_changed.emit()
			ctx.opponent.discard_changed.emit()
		30:
			ctx.effect_handler.log_message.emit(
				"Inherited Life: 30 rage cards — you win the game!")
			ctx.game_state.declare_winner(ctx.owner.player_id)
