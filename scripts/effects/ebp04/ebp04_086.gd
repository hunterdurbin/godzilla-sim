extends CardEffect
# Mechagodzilla City
# <Base>
# <Your Turn> Own counter phase start: for each 5 green battle cards in discard →
# play 1 Valkyrie battle card from discard.


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func is_base_strategy() -> bool:
	return true


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			green_count += 1

	var plays: int = green_count / 5
	if plays == 0:
		return

	for _i in range(plays):
		var found := await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				return CardEnums.CardTrait.VALKYRIE in card.get("traits", []),
			"Play a Valkyrie from your discard pile (or skip):")
		if found.is_empty():
			break
		await ctx.effect_handler.play_from_discard(ctx.owner.player_id, found)
