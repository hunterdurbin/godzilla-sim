extends CardEffect
# Mothra Imago (1992)
# When discarded from hand by opponent's effect + opp monster in zones 4-8 → may play self.
# When discarded from hand by opponent's effects + this is in area 8 → own rage +2.


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_threat"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Only when discarded by opponent's effect
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	if ctx.opponent.monster_zone >= 4:
		await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	# Rage +2 when ANY hand card discarded by opponent + this is in area 8
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7:  # Must be zone 8 (index 7)
		return

	var old_rage := ctx.owner.rage
	ctx.owner.rage += 2
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
