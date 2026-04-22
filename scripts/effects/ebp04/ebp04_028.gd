extends CardEffect
# Gigan (2004)
# <Opponent's Turn> All opp strategy cards gain +3 rank (after play, return to original).
# <Opponent's Turn> Each time your opponent plays a Battle card from their Main deck, your opponent discards until they have 1 card remaining in their hand. 


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


func on_battle_card_played(ctx: EffectContext, _zone_index: int, played_from_deck: bool = false) -> void:
	# <Opponent's Turn> Each time opp plays a battle card from their main deck → discard to 1
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	if not played_from_deck:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent, 1)
