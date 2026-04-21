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


func _find_own_strategy_zone(ctx: EffectContext) -> int:
	var self_id: String = ctx.card_data.get("id", "")
	for i in range(ctx.owner.strategy_zones.size()):
		if ctx.owner.strategy_zones[i].get("id", "") == self_id:
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

	var count_before: int = ctx.effect_handler.get_cards_under_strategy_top(ctx.owner, strategy_idx).size()

	# Move top delta cards from discard pile under this strategy as trackers
	for _i in range(delta):
		if ctx.owner.discard_pile.is_empty():
			break
		var tracker: Dictionary = ctx.owner.discard_pile.pop_back()
		ctx.effect_handler.place_card_under_strategy_zone(ctx.owner, tracker, strategy_idx)
		ctx.owner.discard_changed.emit()

	var count_after: int = ctx.effect_handler.get_cards_under_strategy_top(ctx.owner, strategy_idx).size()

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
