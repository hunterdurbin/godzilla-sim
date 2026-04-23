extends CardEffect
# Mechagodzilla Hangar (Strategy R5)
# <Base>
# <Your Turn> Counter start: search deck for 1 Weapon/Mech battle card, add to hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func is_base_strategy() -> bool:
	return true


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return # Your turn only

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card):
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_any_trait(card, [CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.MECH]),
		"Search for a Weapon or Mech battle card:"
	)
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
