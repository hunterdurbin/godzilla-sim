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
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			if not CardEnums.CardTrait.GODZILLA in card.get("traits", []):
				return false
			return ctx.effect_handler.can_card_be_played(ctx.owner.player_id, card),
		"Play a Godzilla battle card from hand (or skip):",
		true
	)
	if selected.is_empty():
		return

	# select_hand_card moved it to discard — move it from discard to a zone
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("id") == selected.get("id"):
			var card: Dictionary = ctx.owner.discard_pile.pop_at(i)
			ctx.owner.discard_changed.emit()

			var empty := ctx.owner.get_empty_zone_indices()
			if empty.is_empty():
				# No empty zones — let them pick any zone to overwrite
				var all_zones: Array[int] = []
				for zi in range(8):
					all_zones.append(zi)
				var dest := await ctx.effect_handler.select_zone_target(
					ctx.owner.player_id, ctx.owner.player_id, all_zones,
					"Choose a zone to play the battle card:")
				if dest < 0:
					ctx.owner.discard_pile.append(card)
					ctx.owner.discard_changed.emit()
					return
				ctx.owner.push_zone_card(dest, card)
			else:
				var dest := await ctx.effect_handler.select_zone_target(
					ctx.owner.player_id, ctx.owner.player_id, empty,
					"Choose a zone to play the battle card:")
				if dest < 0:
					ctx.owner.discard_pile.append(card)
					ctx.owner.discard_changed.emit()
					return
				ctx.owner.push_zone_card(dest, card)

			ctx.owner.zones_changed.emit()
			await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card)
			break
