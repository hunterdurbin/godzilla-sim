extends CardEffect
# Gigan (2004)
# <Opponent's Turn> All opp strategy cards gain +3 rank (after play, return to original).
# <Opponent's Turn> Each time opp plays a battle card → opp discards to 1.


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, _card: Dictionary, target_player_id: int) -> int:
	# Only affects the opponent's strategies, only on the opponent's turn
	if target_player_id == ctx.owner.player_id:
		return 0
	if ctx.game_state.current_player_id != target_player_id:
		return 0
	return 3


func on_battle_card_played(ctx: EffectContext, _zone_index: int) -> void:
	# <Opponent's Turn> Each time opp plays a battle card → discard to 1
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 1)
