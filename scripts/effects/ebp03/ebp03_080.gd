extends CardEffect
# Odo Island (Strategy R6)
# <Base>
# <Your Turn> Counter start: play up to 1 Godzilla battle card from hand.
#
# Tested: Yes
# Known issues: None
# Edge cases:
#   A chosen card must pass all play restrictions (e.g. EBP01-073 can be played if and only if the card requirement is met)
# Rules: None
# Interactions: Any rank battle card can be played from this effect.
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, effect_handler = null) -> bool:
	var valid_zones := CardEffect.get_effect_play_zones(owner)
	if valid_zones.is_empty():
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
			if effect_handler and not effect_handler.can_card_be_played(owner.player_id, card):
				continue
			return true
	return false


func is_base_strategy() -> bool:
	return true


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return # Your turn only

	# Find Godzilla battle cards in hand (respecting play restrictions)
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card):
			if not CardUtils.is_battle(card):
				return false
			if not CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
				return false
			return ctx.effect_handler.can_card_be_played(ctx.owner.player_id, card),
		tr("STR_EFF_EBP03_080_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	# select_hand_card moved it to discard — move it from discard to a zone
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("id") == selected.get("id"):
			var card: Dictionary = ctx.owner.discard_pile.pop_at(i)
			ctx.owner.discard_changed.emit()

			var valid_zones := CardEffect.get_effect_play_zones(ctx.owner)

			var dest := await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.owner.player_id, valid_zones,
				tr("STR_EFF_PLAY_BATTLE_ZONE"))
			if dest < 0:
				ctx.owner.discard_pile.append(card)
				ctx.owner.discard_changed.emit()
				return

			# Handle overload if zone occupied
			if ctx.owner.zone_has_cards(dest):
				var destroyed_stack: Array = ctx.owner.clear_zone(dest)
				EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
				ctx.owner.discard_changed.emit()

			ctx.owner.push_zone_card(dest, card)
			ctx.owner.zones_changed.emit()
			await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card, true)
			break
