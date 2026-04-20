extends CardEffect
# Gigan (2004)
# <Opponent's Turn> All opp strategy cards gain +3 rank (after play, return to original).
# <Opponent's Turn> Each time opp plays a battle card → opp discards to 1.
# <Opponent's Turn> Opp cannot draw during end phase.
# Note: blocks_opponent_end_phase_draw and strategy rank increase are new mechanisms.
# Strategy rank in hand modifier: TODO wire into RulesEngine.
# End phase draw block: TODO wire into ActionHandler.execute_end_phase().


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	# +3 rank to all opp strategy cards on opponent's turn
	# Note: this method applies to field (in-play) strategies, not hand.
	# Hand modifier is a separate mechanism (EBP04-068 pattern) not yet wired.
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return 0
	return 3


func on_battle_card_played(ctx: EffectContext, _zone_index: int) -> void:
	# <Opponent's Turn> Each time opp plays a battle card → discard to 1
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 1)
