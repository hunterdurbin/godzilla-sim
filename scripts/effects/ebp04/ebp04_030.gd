extends CardEffect
# Modified Gigan
# <Opponent's Turn> Opp cannot draw cards during end phase.
# <Enter> Destroy 1 opp battle card in zones 1-5.
# blocks_opponent_end_phase_draw is wired into ActionHandler.execute_end_phase_draw().


func blocks_opponent_end_phase_draw(ctx: EffectContext) -> bool:
	return ctx.game_state.current_player_id != ctx.owner.player_id


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_enter(ctx: EffectContext) -> void:
	var valid_zones: Array[int] = []
	for i in range(5):
		if ctx.opponent.zone_has_cards(i):
			valid_zones.append(i)
	if valid_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
		"Destroy an opponent's battle card in zones 1-5:")
	if chosen >= 0:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
