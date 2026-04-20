extends CardEffect
# Rodan (2004)
# When discarded from hand by opponent's effect → may play this card.
# <Awakening 6> +3000 counter power.


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_cp"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Only when discarded by opponent's effect (not own turn)
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
