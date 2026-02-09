extends CardEffect
# Godzilla(2001) R1
# <Awakening4> At the beginning of your end phase, discard 1 R5+ battle card to advance 1 zone.
# <Awakening6> +5000 threat level.


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.owner.monster_zone < 4:
		return
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE and card.get("rank", 0) >= 5,
		"Discard a rank 5+ battle card to advance 1 zone (or skip):",
		true
	)
	if not selected.is_empty():
		var old_zone := ctx.owner.monster_zone
		ctx.owner.monster_zone += 1
		ctx.owner.monster_changed.emit()
		await ctx.effect_handler.trigger_monster_advance(ctx.owner.player_id, old_zone, ctx.owner.monster_zone)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 5000
	return 0
