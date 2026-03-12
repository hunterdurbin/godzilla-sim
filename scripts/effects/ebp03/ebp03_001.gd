extends CardEffect
# Godzilla(2001) R1
# <Awakening4> At the beginning of your end phase, discard 1 R5+ battle card to advance 1 zone.
# <Awakening6> +5000 threat level.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_monster", "boosts_threat"]


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
		if ctx.owner.monster_zone < 8:
			await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 6:
		return 5000
	return 0
